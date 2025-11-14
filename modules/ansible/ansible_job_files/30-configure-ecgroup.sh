#!/bin/bash
#
# Ansible Job: Configure ECGroup Cluster (OCI)
#
# This script configures the ECGroup cluster using the provided nodes from the inventory.
# It is idempotent and only configures new nodes based on the inventory.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
INVENTORY_FILE="/var/ansible/trigger/inventory.ini"
STATE_FILE="/var/run/ansible_jobs_status/configured_ecgroup_nodes.txt"  # Track configured ECGroup nodes
ECGROUP_PRIVATE_KEY_PATH="/home/ubuntu/.ssh/ansible_admin_key"

# --- Source the function library ---
if [ ! -f "$ANSIBLE_LIB_PATH" ]; then
  echo "[configure-ecgroup] FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
  exit 1
fi
source "$ANSIBLE_LIB_PATH"

# --- Main Logic ---
echo "[configure-ecgroup] --- Starting Configure ECGroup Cluster Job (OCI) ---"

# 1. Verify inventory file exists

if [ ! -f "$INVENTORY_FILE" ]; then
  echo "[configure-ecgroup] ERROR: Inventory file $INVENTORY_FILE not found." >&2
  exit 1
fi

# 2. Get the ecgroup_metadata_array and the ecgroup_storage_array

eg_md_array=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /ecgroup_metadata_array = / \
{sub(/.*= /, ""); print}' "$INVENTORY_FILE")
eg_storage_array=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /ecgroup_storage_array = / \
{sub(/.*= /, ""); print}' "$INVENTORY_FILE")

echo "[configure-ecgroup] EC_MD_ARRAY = $eg_md_array"
echo "[configure-ecgroup] EC_ST_ARRAY = $eg_storage_array"

# 3. Parse ecgroup_nodes with IPs and names

all_ecgroup_nodes=""
ecgroup_map=() # Array of "IP:name"
flag="0"  # Initialize flag for ecgroup_nodes parsing

while read -r line; do
  if [[ "$line" =~ ^\[ecgroup_nodes\]$ ]]; then
    flag="1"
  elif [[ "$line" =~ ^\[ && ! "$line" =~ ^\[ecgroup_nodes\]$ ]]; then
    flag="0"
  fi
  if [ "$flag" = "1" ] && [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    ip=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | grep -oP 'node_name="\K[^"]+' || echo "${ip//./-}")
    all_ecgroup_nodes+="$ip"$'\n'
    ecgroup_map+=("$ip:$name")
  fi
done < "$INVENTORY_FILE"

all_ecgroup_nodes=$(echo "$all_ecgroup_nodes" | grep -v '^$' | sort -u || true)

# Debug: Log parsed IPs

echo "[configure-ecgroup] Parsed ecgroup_nodes: $all_ecgroup_nodes"

if [ -z "$all_ecgroup_nodes" ]; then
  echo "[configure-ecgroup] No ecgroup_nodes found in inventory. Exiting."
  exit 0
fi

all_hosts=$(echo -e "$all_ecgroup_nodes" | sort -u)
echo "[configure-ecgroup] All Hosts: $all_hosts"

# 4. Identify new hosts (ecgroup_nodes not in state)

mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
new_hosts=()
for host in $all_hosts; do
  if ! grep -q -F -x "$host" "$STATE_FILE"; then
    new_hosts+=("$host")
  fi
done

# If new hosts, run configuration

if [ ${#new_hosts[@]} -gt 0 ]; then
  echo "[configure-ecgroup] Found ${#new_hosts[@]} new ECGroup nodes: ${new_hosts[*]}. Configuring them."

  # 5. Build ECGroup hosts list (IPs) and nodes list (names) from map

  ecgroup_hosts=""
  ecgroup_nodes=""
  for entry in "${ecgroup_map[@]}"; do
    ip=$(echo "$entry" | cut -d: -f1)
    name=$(echo "$entry" | cut -d: -f2-)
    ecgroup_hosts+="$ip "
    ecgroup_nodes+="$name "
  done
  ecgroup_hosts="${ecgroup_hosts% }"
  ecgroup_nodes="${ecgroup_nodes% }"

  echo "[configure-ecgroup] ECGroup Hosts: $ecgroup_hosts"
  echo "[configure-ecgroup] ECGroup Nodes: $ecgroup_nodes"

  # Assume ECGROUP_METADATA_ARRAY and ECGROUP_STORAGE_ARRAY are parsed or hardcoded; adjust as needed
  # For example, derive from inventory or vars if available

  ECGROUP_METADATA_ARRAY="${eg_md_array}"
  ECGROUP_STORAGE_ARRAY="${eg_storage_array}"
  ECGROUP_USER="debian"              # debian user for ECGroup instances on OCI
  ROOT_USER="root"                   # root user needed for ssh

  # 6. Create temporary ECGroup inventory

  tmp_inventory=$(mktemp)
  echo "[ecgroup]" > "$tmp_inventory"
  for host in $ecgroup_hosts; do
    echo "$host ansible_user=$ECGROUP_USER ansible_ssh_private_key_file=$ECGROUP_PRIVATE_KEY_PATH" >> "$tmp_inventory"
  done

  echo "[configure-ecgroup] --- Inventory File: $tmp_inventory"
  cat "$tmp_inventory"

  # 7. Combined playbook for configuring ECGroup (OCI-optimized)

  tmp_playbook=$(mktemp)
  cat > "$tmp_playbook" <<EOF
- name: Configure ECGroup from the OCI controller node
  hosts: ecgroup
  gather_facts: false
  vars:
    ecgroup_name: "ecg"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  become: true
  tasks:
    - name: Wait for SSH to be available
      wait_for_connection:
        delay: 10
        timeout: 600

    - name: Create the cluster
      shell: >
        /opt/rozofs-installer/rozo_rozofs_create.sh -n {{ ecgroup_name }} -s "$ecgroup_hosts" -t external -d 3
      register: create_cluster_result
      retries: 3
      delay: 10
      until: create_cluster_result.rc == 0

    - name: Add CTDB nodes
      shell: >
        /opt/rozofs-installer/rozo_rozofs_ctdb_node_add.sh -n {{ ecgroup_name }} -c "$ecgroup_hosts"
      register: ctdb_node_add_result
      retries: 3
      delay: 10
      until: ctdb_node_add_result.rc == 0

    - name: Setup DRBD
      shell: >
        /opt/rozofs-installer/rozo_drbd.sh -y -n {{ ecgroup_name }} -d "$ECGROUP_METADATA_ARRAY"
      register: drbd_result
      retries: 3
      delay: 10
      until: drbd_result.rc == 0

    - name: Create the array
      shell: >
        /opt/rozofs-installer/rozo_compute_cluster_balanced.sh -y -n {{ ecgroup_name }} -d "$ECGROUP_STORAGE_ARRAY"
      register: compute_cluster_result
      retries: 3
      delay: 10
      until: compute_cluster_result.rc == 0

    - name: Propagate the configuration
      shell: >
        /opt/rozofs-installer/rozo_rozofs_install.sh -n {{ ecgroup_name }}
      register: install_result
      retries: 3
      delay: 10
      until: install_result.rc == 0
  run_once: true
EOF

  # 8. Run the Ansible playbook

  echo "[configure-ecgroup] Running Ansible playbook to configure ECGroup..."
  ansible-playbook "$tmp_playbook" -i "$tmp_inventory"

  # 9. Update state file with new hosts

  echo "Playbook finished. Updating state file with new ECGroup nodes..."
  for host in "${new_hosts[@]}"; do
    echo "$host" >> "$STATE_FILE"
  done

  # 10. Clean up

  rm -f "$tmp_inventory" "$tmp_playbook"

else
  echo "[configure-ecgroup] No new ECGroup nodes detected. Exiting."
fi

echo "[configure-ecgroup] --- Configure ECGroup Cluster Job Complete (OCI) ---"
