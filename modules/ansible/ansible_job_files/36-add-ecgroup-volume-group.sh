#!/bin/bash
#
# Ansible Job: Manage ECGroup Volume Group (OCI)
#
# This script creates the ECGroup volume group if missing or updates it.
# It only runs if ecgroup_add_to_hammerspace is true.
# It is idempotent and only updates if necessary.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/ecgroup_volume_group_state.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Manage ECGroup Volume Group Job (OCI) ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Check if ECGroup should be added to Hammerspace
ecgroup_add_to_hammerspace=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_add_to_hammerspace = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")

if [ "$ecgroup_add_to_hammerspace" != "true" ]; then
  echo "ECGroup integration with Hammerspace is DISABLED. Skipping volume group creation."
  exit 0
fi

echo "ECGroup integration with Hammerspace is ENABLED. Proceeding with volume group management."

# 3. Get the username, password, and ECGroup volume group name from the inventory
hs_username=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_username = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
hs_password=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_password = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_volume_group_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_volume_group_name = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")

# Debug: Echo parsed vars
echo "Parsed hs_username: $hs_username"
echo "Parsed hs_password: [REDACTED]"
echo "Parsed ecgroup_volume_group_name: $ecgroup_volume_group_name"

# Check if ECGroup VG name is provided
if [ -z "$ecgroup_volume_group_name" ]; then
  echo "No ECGroup volume group name specified. Skipping."
  exit 0
fi

HS_USERNAME=$hs_username
HS_PASSWORD=$hs_password
HS_VOLUME_GROUP=$ecgroup_volume_group_name

# 4. Parse hammerspace
all_hammerspace=""
flag="0"
while read -r line; do
  if [[ "$line" =~ ^\[hammerspace\]$ ]]; then
    flag="hammerspace"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[hammerspace\]$ ]]; then
    flag="0"
  fi
  if [ "$flag" = "hammerspace" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    all_hammerspace+="$line"$'\n'
  fi
done < "$INVENTORY_FILE"

all_hammerspace=$(echo "$all_hammerspace" | grep -v '^$' | sort -u || true)

if [ -z "$all_hammerspace" ]; then
  echo "No hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# 5. Get ECGroup node name (should be "ecgroup-cluster")
ecgroup_node_name="ecgroup-cluster"

# Build VG node location for ECGroup
vg_node_locations="[{ \"_type\": \"NODE_LOCATION\", \"node\": { \"_type\": \"NODE\", \"name\": \"$ecgroup_node_name\" } }]"

# Check state
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
saved_vg_name=$(cat "$STATE_FILE" || echo "")

if [ "$HS_VOLUME_GROUP" == "$saved_vg_name" ]; then
  echo "ECGroup volume group already up to date. Exiting."
  exit 0
fi

echo "ECGroup volume group needs creation/update: $HS_VOLUME_GROUP"

# Playbook for create/update VG
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    volume_group_name: "$HS_VOLUME_GROUP"
    vg_node_locations: $vg_node_locations
    ecgroup_node_name: "$ecgroup_node_name"

  tasks:
    - name: Wait for ECGroup node to be available
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/nodes"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: nodes_check
      until: >-
        (
          nodes_check.json
          | selectattr('name', 'equalto', ecgroup_node_name)
          | selectattr('nodeType', 'equalto', 'OTHER')
          | selectattr('nodeState', 'equalto', 'MANAGED')
          | list
          | length
        ) > 0
      retries: 60
      delay: 10

    - name: Get all volume groups
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: volume_groups_response
      until: volume_groups_response.status == 200
      retries: 30
      delay: 10

    - name: Set fact for VG exists
      set_fact:
        vg_exists: "{{ volume_group_name in (volume_groups_response.json | map(attribute='name') | list) }}"

    - name: Create volume group if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups"
        method: POST
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: not vg_exists
      register: vg_create
      until: vg_create.status == 200
      retries: 30
      delay: 10

    - name: Update volume group if exists
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups/{{ volume_group_name }}"
        method: PUT
        body: >-
          {{
            {
              "name": volume_group_name,
              "_type": "VOLUME_GROUP",
              "expressions": [
                {
                  "operator": "IN",
                  "locations": vg_node_locations
                }
              ]
            }
          }}
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: vg_exists
      register: vg_update
      until: vg_update.status == 200
      retries: 30
      delay: 10
EOF

echo "Running Ansible playbook to manage ECGroup volume group..."
ansible-playbook "$tmp_playbook"

# Update state
echo "$HS_VOLUME_GROUP" > "$STATE_FILE"

# Clean up
rm -f "$tmp_playbook"

echo "--- Manage ECGroup Volume Group Job Complete (OCI) ---"
