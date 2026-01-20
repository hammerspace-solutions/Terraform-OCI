#!/bin/bash
#
# Ansible Job: Create ECGroup Share
#
# This script creates the ECGroup share if not existing.
# It only runs if ecgroup_add_to_hammerspace is true.
# It is idempotent.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/created_ecgroup_shares.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Create ECGroup Share(s) Job ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Check if ECGroup should be added to Hammerspace
ecgroup_add_to_hammerspace=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_add_to_hammerspace = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")

if [ "$ecgroup_add_to_hammerspace" != "true" ]; then
  echo "ECGroup integration with Hammerspace is DISABLED. Skipping share creation."
  exit 0
fi

echo "ECGroup integration with Hammerspace is ENABLED. Proceeding with share creation."

# 3. Get the username, password, volume group, and share configuration from the inventory
hs_username=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_username = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
hs_password=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^hs_password = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_volume_group_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_volume_group_name = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_share_name=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_share_name = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_share_path=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_share_path = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_share_export_path=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_share_export_path = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")
ecgroup_share_description=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /^ecgroup_share_description = / {sub(/.*= /, ""); print; exit}' "$INVENTORY_FILE")

# Check if ECGroup share name is provided
if [ -z "$ecgroup_share_name" ]; then
  echo "No ECGroup share name specified. Skipping."
  exit 0
fi

# Set defaults if not provided
ecgroup_share_path="${ecgroup_share_path:-/$ecgroup_share_name}"
ecgroup_share_export_path="${ecgroup_share_export_path:-/$ecgroup_share_name}"
ecgroup_share_description="${ecgroup_share_description:-ECGroup share}"

# Debug: Echo parsed vars
echo "Parsed hs_username: $hs_username"
echo "Parsed hs_password: [REDACTED]"
echo "Parsed ecgroup_volume_group_name: $ecgroup_volume_group_name"
echo "Parsed ecgroup_share_name: $ecgroup_share_name"
echo "Parsed ecgroup_share_path: $ecgroup_share_path"
echo "Parsed ecgroup_share_export_path: $ecgroup_share_export_path"
echo "Parsed ecgroup_share_description: $ecgroup_share_description"

# Set variables for later use
HS_USERNAME=$hs_username
HS_PASSWORD=$hs_password
HS_VOLUME_GROUP=$ecgroup_volume_group_name
HS_SHARE_NAME=$ecgroup_share_name
HS_SHARE_PATH=$ecgroup_share_path
HS_EXPORT_PATH=$ecgroup_share_export_path
HS_SHARE_DESC=$ecgroup_share_description

SHARE_BODY='{'
SHARE_BODY+='"name": "'$HS_SHARE_NAME'",'
SHARE_BODY+='"path": "'$HS_SHARE_PATH'",'
SHARE_BODY+='"exportPath": "'$HS_EXPORT_PATH'",'
SHARE_BODY+='"comment": "'$HS_SHARE_DESC'",'
SHARE_BODY+='"maxShareSize": "0",'
SHARE_BODY+='"alertThreshold": "90",'
SHARE_BODY+='"maxShareSizeType": "TB",'
SHARE_BODY+='"smbAliases": [],'
SHARE_BODY+='"exportOptions": [{"subnet": "'*'", "rootSquash": "false", "accessPermissions": "RW"}],'
SHARE_BODY+='"shareSnapshots": [],'
SHARE_BODY+='"shareObjectives": [{"objective": {"name": "no-atime"}, "applicability": "TRUE"},'
SHARE_BODY+='{"objective": {"name": "confine-to-'$HS_VOLUME_GROUP'"}, "applicability": "TRUE"}],'
SHARE_BODY+='"smbBrowsable": "true", "shareSizeLimit": "0"'
SHARE_BODY+='}'

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

# Check if share already exists in state
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

if grep -qF "$HS_SHARE_NAME" "$STATE_FILE"; then
  echo "ECGroup share '$HS_SHARE_NAME' already created. Exiting."
  exit 0
fi

echo "Creating ECGroup share: $HS_SHARE_NAME"

# Create playbook
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    share_name: "$HS_SHARE_NAME"
    share_body: $SHARE_BODY
    volume_group_name: "$HS_VOLUME_GROUP"

  tasks:
    - name: Wait for volume group to be available (if specified)
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
      register: vg_check
      until: >-
        (
          vg_check.json
          | selectattr('name', 'equalto', volume_group_name)
          | list
          | length
        ) > 0
      retries: 60
      delay: 10
      when: volume_group_name != ""

    - name: Get all shares
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        return_content: true
        status_code: 200
        body_format: json
        timeout: 30
      register: shares_response
      until: shares_response.status == 200
      retries: 30
      delay: 10

    - name: Check if share exists
      set_fact:
        share_exists: "{{ share_name in (shares_response.json | map(attribute='name') | list) }}"

    - name: Create share if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: POST
        body: "{{ share_body }}"
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 202
        body_format: json
        validate_certs: false
        timeout: 30
      when: not share_exists
      register: share_create
      until: share_create.status == 202
      retries: 30
      delay: 10

    - name: Wait for share creation to complete
      uri:
        url: "{{ share_create.location }}"
        method: GET
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        validate_certs: false
        status_code: 200
        body_format: json
        timeout: 30
      register: _result
      until: _result.json.status == "COMPLETED"
      retries: 30
      delay: 10
      when: not share_exists and share_create.status == 202

    - name: Display result
      debug:
        msg: "ECGroup share '{{ share_name }}' {{ 'already exists' if share_exists else 'created successfully' }}"
EOF

echo "Running Ansible playbook to create ECGroup share..."
ansible-playbook "$tmp_playbook"

# Update state if not already there
if ! grep -qF "$HS_SHARE_NAME" "$STATE_FILE"; then
  echo "$HS_SHARE_NAME" >> "$STATE_FILE"
  echo "State file updated with share: $HS_SHARE_NAME"
fi

# Clean up
rm -f "$tmp_playbook"

echo "--- Create ECGroup Share Job Complete ---"
