#!/bin/bash
#
# Ansible Job: Add Storage Volumes
#
# This script adds non-reserved logical volumes from storage nodes if not already added.
# It is idempotent and only adds new volumes.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/added_storage_volumes.txt" # Track added volume names

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "--- Starting Add Storage Volumes Job ---"

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

# Read existing added volumes from STATE_FILE
touch "$STATE_FILE"
existing_volumes=()
while IFS= read -r line; do
  existing_volumes+=("$line")
done < "$STATE_FILE"

# Convert to JSON array for playbook var
existing_volumes_json=$(printf '%s\n' "${existing_volumes[@]}" | jq -R . | jq -s .)

# Playbook to get non-reserved volumes, add missing
tmp_playbook=$(mktemp)
cat > "$tmp_playbook" <<EOF
- hosts: localhost
  gather_facts: false
  vars:
    hs_username: "$HS_USERNAME"
    hs_password: "$HS_PASSWORD"
    data_cluster_mgmt_ip: "$data_cluster_mgmt_ip"
    existing_volumes: $existing_volumes_json

  tasks:
    - name: Get all nodes
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
      register: nodes_response
      until: nodes_response.status == 200
      retries: 60
      delay: 30

    - name: Filter OTHER nodes
      set_fact:
        other_nodes: "{{ nodes_response.json | selectattr('nodeType', 'equalto', 'OTHER') | list }}"

    - name: Extract non-reserved logical volumes
      set_fact:
        non_reserved_volumes: >-
          {{
            other_nodes
            | map(attribute='platformServices')
            | flatten
            | selectattr('_type', 'equalto', 'LOGICAL_VOLUME')
            | selectattr('reserved', 'equalto', false)
            | list
          }}

    - name: Create volumes for addition (filter out existing)
      set_fact:
        volumes_for_add_json: |
          [
            {% for item in non_reserved_volumes %}
              {% set full_name = item.node.name ~ ':/' ~ item.exportPath %}
              {% if full_name not in existing_volumes %}
                {
                  "name": "{{ item.node.name }}::{{ item.exportPath }}",
                  "logicalVolume": {
                    "name": "{{ item.exportPath }}",
                    "_type": "LOGICAL_VOLUME"
                  },
                  "node": {
                    "name": "{{ item.node.name }}",
                    "_type": "NODE"
                  },
                  "_type": "STORAGE_VOLUME",
                  "accessType": "READ_WRITE",
                  "storageCapabilities": {
                    "performance": {
                        "utilizationThreshold": 0.95,
                        "utilizationEvacuationThreshold": 0.9
                    }
                  }
                }{% if not loop.last %},{% endif %}
              {% endif %}
            {% endfor %}
          ]

    - name: Parse volumes JSON
      set_fact:
        volumes_for_add: "{{ volumes_for_add_json | from_json }}"

    - name: Check if there are volumes to add
      set_fact:
        has_volumes_to_add: "{{ volumes_for_add | length > 0 }}"

    - name: Add storage volumes
      block:
        - name: Check storage system
          uri:
            url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/nodes/{{ item.node.name|urlencode }}"
            method: GET
            user: "{{ hs_username }}"
            password: "{{ hs_password }}"
            force_basic_auth: true
            validate_certs: false
            status_code: 200
            timeout: 30
          register: __node_results
          until: __node_results.status == 200
          retries: 30
          delay: 10
          loop: "{{ volumes_for_add }}"

        - name: Add volume
          uri:
            url: "https://{{ data_cluster_mgmt_ip }}:8443/mgmt/v1.2/rest/storage-volumes?force=true&skipPerfTest=false&createPlacementObjectives=true"
            method: POST
            body: '{{ item }}'
            user: "{{ hs_username }}"
            password: "{{ hs_password }}"
            force_basic_auth: true
            status_code: 202
            body_format: json
            validate_certs: false
            timeout: 30
          register: __results
          until: __results.status == 202
          retries: 30
          delay: 10
          loop: "{{ volumes_for_add }}"

        - name: Wait for completion
          uri:
            url: "{{ item.location }}"
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
          delay: 20
          when: item.status == 202
          loop: "{{ __results.results }}"

        - name: Extract added volume names (in desired format)
          set_fact:
            added_volume_names: >-
              [
                {% for item in volumes_for_add %}
                  "{{ item.node.name }}:/{{ item.logicalVolume.name }}"{% if not loop.last %},{% endif %}
                {% endfor %}
              ]

        - name: Write volumes to state file
          lineinfile:
            path: "$STATE_FILE"
            line: "{{ item.node.name }}:/{{ item.logicalVolume.name }}"
            create: yes
            state: present
          loop: "{{ volumes_for_add }}"

        - name: Output added volumes
          debug:
            msg: "{{ added_volume_names }}"

      when: has_volumes_to_add
EOF

  echo "Running Ansible playbook to add storage volumes..."
  ansible-playbook "$tmp_playbook"

  # Clean up
  rm -f "$tmp_playbook"

  echo "--- Add Storage Volumes Job Complete ---"
