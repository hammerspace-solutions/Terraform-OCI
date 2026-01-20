#!/bin/bash
#
# Ansible Job: Manage Volume Group (OCI)
#
# This script creates the volume group if missing or updates it to include new node locations.
# It is idempotent and only updates if necessary.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/volume_group_state.txt" # Track current nodes in VG

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Manage Volume Group Job (OCI) ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Get the username, password, volume group, and share name from the inventory

 hs_username=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_username = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
 hs_password=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_password = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
volume_group_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^volume_group_name = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
share_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^share_name = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")

# Debug: Echo parsed vars
echo "Parsed hs_username: $hs_username"
echo "Parsed hs_password: [REDACTED]"
echo "Parsed volume_group_name: $volume_group_name"
echo "Parsed share_name: $share_name"

# Set variables for later use

HS_USERNAME=$hs_username
HS_PASSWORD=$hs_password
HS_VOLUME_GROUP=$volume_group_name
HS_SHARE=$share_name

# 3. Parse hammerspace and storage_servers with names (assuming inventory has IP node_name="name")

all_hammerspace=""
flag="0"  # Initialize flag for hammerspace parsing
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

all_storage_servers=""
storage_map=() # Array of "IP:name"
flag="0"  # Initialize flag for storage_servers parsing
while read -r line; do
  if [[ "$line" =~ ^\[storage_servers\]$ ]]; then
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[storage_servers\]$ ]]; then
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    # Note: This assumes inventory lines have node_name="..." format
    # If not, you'll need to adjust how you get the node name
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    all_storage_servers+="$ip"$'\n'
    storage_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_hammerspace=$(echo "$all_hammerspace" | grep -v '^$' | sort -u || true)
all_storage_servers=$(echo "$all_storage_servers" | grep -v '^$' | sort -u || true)

# Debug: Log parsed IPs

echo "Parsed hammerspace: $all_hammerspace"
echo "Parsed storage_servers: $all_storage_servers"

if [ -z "$all_storage_servers" ] || [ -z "$all_hammerspace" ]; then
  echo "No storage_servers or hammerspace found in inventory. Exiting."
  exit 0
fi

data_cluster_mgmt_ip=$(echo "$all_hammerspace" | head -1)

# Build current node names from storage_map
current_nodes=()
for entry in "${storage_map[@]}"; do
  name=$(echo "$entry" | cut -d: -f2-)
  current_nodes+=("$name")
done
current_nodes_str=$(printf "%s\n" "${current_nodes[@]}" | sort | tr '\n' ',')

# Check state
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
saved_nodes_str=$(cat "$STATE_FILE" | tr '\n' ',' || echo "")

if [ "$current_nodes_str" == "$saved_nodes_str" ]; then
  echo "Volume group already up to date with current nodes. Exiting."
  exit 0
fi

echo "Volume group needs update for nodes: ${current_nodes[*]}"

# Build vg_node_locations
vg_node_locations="["
for entry in "${storage_map[@]}"; do
  name=$(echo "$entry" | cut -d: -f2-)
  vg_node_locations+="{ \"_type\": \"NODE_LOCATION\", \"node\": { \"_type\": \"NODE\", \"name\": \"$name\" } },"
done
vg_node_locations="${vg_node_locations%,}]"

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

  tasks:
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

    - name: Get existing volume group
      set_fact:
        existing_vg: "{{ volume_groups_response.json | selectattr('name', 'equalto', volume_group_name) | list | first | default(none) }}"

    - name: Set fact for VG exists
      set_fact:
        vg_exists: "{{ existing_vg is not none }}"

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

    - name: Build updated volume group object (preserves uoid and other required fields)
      set_fact:
        updated_vg: "{{ existing_vg | combine({'expressions': [{'operator': 'IN', 'locations': vg_node_locations}]}, recursive=True) }}"
      when: vg_exists

    - name: Update volume group if exists
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/volume-groups/{{ volume_group_name }}"
        method: PUT
        body: "{{ updated_vg }}"
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 200
        body_format: json
        validate_certs: false
        timeout: 30
      when: vg_exists and updated_vg is defined
      register: vg_update
      until: vg_update.status == 200
      retries: 30
      delay: 10

    - name: Wait until volume group contains all nodes
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
      register: volume_groups_updated
      until: >-
        (
          volume_groups_updated.json
          | selectattr('name', 'equalto', volume_group_name)
          | map(attribute='expressions')
          | map('first')
          | map(attribute='locations')
          | map('map', attribute='node')
          | map('map', attribute='name')
          | list
          | first
          | sort
        ) == (vg_node_locations | map(attribute='node') | map(attribute='name') | list | sort)
      retries: 30
      delay: 10
EOF

  echo "Running Ansible playbook to manage volume group..."
  ansible-playbook "$tmp_playbook"

  # Update state
  printf "%s\n" "${current_nodes[@]}" > "$STATE_FILE"

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Manage Volume Group Job Complete (OCI) ---"

