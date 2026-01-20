#!/bin/bash
#
# Ansible Job: Create Share
#
# This script creates the share if not existing.
# It is idempotent.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/created_shares.txt"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Create Share(s) Job ---"

# 1. Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Get the username, password, volume group, and share name from the inventroy

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
HS_SHARE_NAME=$share_name

SHARE_BODY='{'
SHARE_BODY+='"name": "'$HS_SHARE_NAME'",'
SHARE_BODY+='"path": "/'$HS_SHARE_NAME'",'
SHARE_BODY+='"maxShareSize": "0",'
SHARE_BODY+='"alertThreshold": "90",'
SHARE_BODY+='"maxShareSizeType": "TB",'
SHARE_BODY+='"smbAliases": [],'
SHARE_BODY+='"exportOptions": [{"subnet": "'*'", "rootSquash": "false", "accessPermissions": "RW"}],'
SHARE_BODY+='"shareSnapshots": [],'
if [ -n "$HS_VOLUME_GROUP" ]; then
  SHARE_BODY+='"shareObjectives": [{"objective": {"name": "no-atime"}, "applicability": "TRUE"},'
  SHARE_BODY+='{"objective": {"name": "confine-to-'$HS_VOLUME_GROUP'"}, "applicability": "TRUE"}],'
else
  SHARE_BODY+='"shareObjectives": [{"objective": {"name": "no-atime"}, "applicability": "TRUE"}],'
fi
SHARE_BODY+='"smbBrowsable": "true", "shareSizeLimit": "0"'
SHARE_BODY+='}'

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

if grep -q -F -x "$HS_SHARE_NAME" "$STATE_FILE"; then
  echo "Share $HS_SHARE_NAME already created. Exiting."
  exit 0
fi

# Playbook for create share
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
---
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    share_name: "$HS_SHARE_NAME"
    share: $SHARE_BODY

  tasks:
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

    - name: Set fact for share exists
      set_fact:
        share_exists: "{{ share_name in (shares_response.json | map(attribute='name') | list) }}"

    - name: Create share if missing
      uri:
        url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/shares"
        method: POST
        body: '{{ share }}'
        user: "{{ hs_username }}"
        password: "{{ hs_password }}"
        force_basic_auth: true
        status_code: 202
        body_format: json
        validate_certs: false
        timeout: 30
      register: share_create
      until: share_create.status == 202
      retries: 30
      delay: 10
      when: not share_exists

    - name: Wait for completion
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
      when: share_create.status == 202
EOF

  echo "Running Ansible playbook to create share..."
  ansible-playbook "$tmp_playbook"

  # Update state
  echo "$HS_SHARE_NAME" >> "$STATE_FILE"

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Create Share Job Complete ---"
  
