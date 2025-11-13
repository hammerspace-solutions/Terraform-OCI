#!/bin/bash

# OCI Ansible Configuration Script
# Updated for Oracle Cloud Infrastructure compatibility

# Variable placeholders - replaced by Terraform templatefile function
TARGET_NODES_JSON='${TARGET_NODES_JSON}'
ADMIN_PRIVATE_KEY='${ADMIN_PRIVATE_KEY}'

# --- Script ---
set -euo pipefail

# Retry function for apt operations
retry_apt() {
    local max_attempts=5
    local wait_time=10
    
    for i in $(seq 1 $max_attempts); do
        if "$@"; then
            return 0
        fi
        echo "Attempt $i failed, waiting $${wait_time}s..."
        sleep $wait_time
    done
    return 1
}

# Detect OS and configure package manager
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    # Oracle Linux or RHEL-based systems
    PKG_MGR="dnf"
    if ! command -v dnf &> /dev/null; then
        PKG_MGR="yum"
    fi
    OS_TYPE="oracle"
    
    # Update system and install required packages
    sudo $PKG_MGR -y update
    sudo $PKG_MGR -y install epel-release || true
    sudo $PKG_MGR install -y python3-pip git bc screen net-tools wget curl
    
    # Install Ansible for Oracle Linux
    sudo $PKG_MGR install -y ansible python3-jq || {
        # Fallback: install via pip if package manager fails
        sudo python3 -m pip install ansible jq
    }
    
    # Install jq if not available via package manager
    if ! command -v jq &> /dev/null; then
        sudo python3 -m pip install jq
    fi
    
else
    # Ubuntu/Debian systems
    OS_TYPE="debian"
    
    # Update system and install required packages
    retry_apt sudo apt-get -y update
    retry_apt sudo apt-get install -y python3-pip git bc screen net-tools wget curl
    retry_apt sudo apt-get install -y software-properties-common
    retry_apt sudo add-apt-repository --yes --update ppa:ansible/ansible
    retry_apt sudo apt-get install -y ansible jq
fi

# Upgrade all the installed packages
echo "Upgrading OS to ensure latest packages..."
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y upgrade
else
    retry_apt sudo apt-get -y upgrade
fi



# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"

# Set default user for OCI if not specified
if [ -z "$TARGET_USER" ]; then
    if [ "$OS_TYPE" = "oracle" ]; then
        TARGET_USER="opc"
        TARGET_HOME="/home/opc"
    else
        TARGET_USER="ubuntu"
        TARGET_HOME="/home/ubuntu"
    fi
fi

# Configure SSH settings optimized for OCI
echo "Configuring SSH settings for OCI..."
sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF

# Create NFS test mountpoint
sudo mkdir -p /mnt/nfs-test
sudo chmod 777 /mnt/nfs-test

# Create Hammerspace mountpoint
sudo mkdir -p /mnt/hammerspace
sudo chmod 777 /mnt/hammerspace

# SSH Key Management
echo "Managing SSH keys for OCI..."
if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "${TARGET_HOME}/.ssh"
    chmod 700 "${TARGET_HOME}/.ssh"
    touch "${TARGET_HOME}/.ssh/authorized_keys"
    
    # Process keys one by one to avoid multi-line issues
    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" "${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$key" >> "${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done

    chmod 600 "${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.ssh"
fi

# Install required Ansible collections
echo "Installing required Ansible collections..."
if [ "$TARGET_USER" = "ubuntu" ]; then
    sudo -u ubuntu ansible-galaxy collection install community.crypto
else
    sudo -u $TARGET_USER ansible-galaxy collection install community.crypto
fi

# Configure Ansible for OCI environment
echo "Configuring Ansible for OCI..."
ANSIBLE_USER=$TARGET_USER
ANSIBLE_HOME=$TARGET_HOME

# Create the inventory file for Ansible
INVENTORY_FILE="${ANSIBLE_HOME}/inventory.ini"
echo "[all_nodes]" > "$INVENTORY_FILE"

# Parse the JSON passed from Terraform and create the inventory list
echo "$TARGET_NODES_JSON" | jq -r '.[] | .private_ip' >> "$INVENTORY_FILE"
chown $ANSIBLE_USER:$ANSIBLE_USER "$INVENTORY_FILE"

# Write the private key for Ansible to use for its initial connection
PRIVATE_KEY_FILE="${ANSIBLE_HOME}/.ssh/ansible_admin_key"
mkdir -p ${ANSIBLE_HOME}/.ssh
echo "$ADMIN_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
chown -R $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/.ssh

# Create Ansible configuration file optimized for OCI
cat > ${ANSIBLE_HOME}/ansible.cfg << EOF
[defaults]
host_key_checking = False
inventory = inventory.ini
remote_user = $ANSIBLE_USER
private_key_file = ~/.ssh/ansible_admin_key
timeout = 30
gathering = smart
fact_caching = memory
retry_files_enabled = False
log_path = /var/log/ansible.log

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o ServerAliveInterval=60
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
EOF

chown $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/ansible.cfg

#############################################################################
# Deploy Modular Ansible Job Scripts
#############################################################################

echo "Deploying modular Ansible job scripts..."

# Create directories for ansible jobs and state tracking
sudo mkdir -p /usr/local/ansible/jobs
sudo mkdir -p /usr/local/lib
sudo mkdir -p /var/run/ansible_jobs_status
sudo mkdir -p /var/ansible/trigger

# Deploy ansible function library
%{ for filename, content in ANSIBLE_JOB_FILES ~}
%{ if filename == "ansible_functions.sh" ~}
echo "Deploying ${filename}..."
echo "${content}" | base64 -d | sudo tee /usr/local/lib/ansible_functions.sh > /dev/null
sudo chmod +x /usr/local/lib/ansible_functions.sh
%{ endif ~}
%{ endfor ~}

# Deploy job scripts
%{ for filename, content in ANSIBLE_JOB_FILES ~}
%{ if filename != "ansible_functions.sh" && filename != "README.md" && filename != "TERRAFORM_INTEGRATION.md" ~}
echo "Deploying ${filename}..."
echo "${content}" | base64 -d | sudo tee /usr/local/ansible/jobs/${filename} > /dev/null
sudo chmod +x /usr/local/ansible/jobs/${filename}
%{ endif ~}
%{ endfor ~}

echo "Ansible job scripts deployed successfully."

#############################################################################
# Create Inventory File for Job Scripts
#############################################################################

echo "Creating inventory file for Ansible job scripts..."

# Get ECGroup variables
ECGROUP_INSTANCES="${ECGROUP_INSTANCES}"
ECGROUP_NODES="${ECGROUP_NODES}"
ECGROUP_METADATA_ARRAY="${ECGROUP_METADATA_ARRAY}"
ECGROUP_STORAGE_ARRAY="${ECGROUP_STORAGE_ARRAY}"

# Check if we have storage instances
STORAGE_COUNT=$(echo '${STORAGE_INSTANCES}' | jq '. | length')
ECGROUP_INSTANCES_ARRAY=($ECGROUP_INSTANCES)
ECGROUP_NODES_ARRAY=($ECGROUP_NODES)

# Create inventory file at /var/ansible/trigger/inventory.ini
cat > /var/ansible/trigger/inventory.ini << 'INV_EOF'
[all:vars]
hs_username = admin@localdomain
hs_password = ${ADMIN_USER_PASSWORD}
volume_group_name = ${VG_NAME}
share_name = ${SHARE_NAME}
ecgroup_metadata_array = ${ECGROUP_METADATA_ARRAY}
ecgroup_storage_array = ${ECGROUP_STORAGE_ARRAY}

[hammerspace]
INV_EOF

# Add Hammerspace/Anvil IPs if available
if [ -n "${MGMT_IP}" ]; then
    echo "${MGMT_IP}" >> /var/ansible/trigger/inventory.ini
fi

# Add storage_servers section
echo "" >> /var/ansible/trigger/inventory.ini
echo "[storage_servers]" >> /var/ansible/trigger/inventory.ini

# Add storage instances if available
if [ "$STORAGE_COUNT" -gt 0 ]; then
    echo '${STORAGE_INSTANCES}' | jq -r '.[] | .private_ip + " node_name=\"" + .name + "\""' >> /var/ansible/trigger/inventory.ini
fi

# Add ecgroup_nodes section
echo "" >> /var/ansible/trigger/inventory.ini
echo "[ecgroup_nodes]" >> /var/ansible/trigger/inventory.ini

# Add ECGroup nodes if available
if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "$${!ECGROUP_NODES_ARRAY[@]}"; do
        instance_name="$${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}"
        node_ip="$${ECGROUP_NODES_ARRAY[$i]}"
        echo "$node_ip node_name=\"$instance_name\"" >> /var/ansible/trigger/inventory.ini
    done
fi

echo "Inventory file created at /var/ansible/trigger/inventory.ini"
cat /var/ansible/trigger/inventory.ini

# Build the Anvil ansible playbook variables for OCI (for backward compatibility)
cat > /tmp/anvil.yml << EOF
data_cluster_mgmt_ip: "${MGMT_IP}"
hsuser: admin
password: "${ADMIN_USER_PASSWORD}"
volume_group_name: "${VG_NAME}"
share_name: "${SHARE_NAME}"
oci_environment: true
oci_region: "$${OCI_REGION:-}"
oci_compartment_id: "$${OCI_COMPARTMENT_ID:-}"
EOF

# Build the Nodes ansible playbook for OCI (for backward compatibility)
# Handle all scenarios: storage only, ecgroup only, both, or none

# Start creating nodes.yml
echo "storages:" > /tmp/nodes.yml

# Add storage instances if available
if [ "$STORAGE_COUNT" -gt 0 ]; then
    echo '${STORAGE_INSTANCES}' | jq -r '
      map(
        "- name: \"" + .name + "\"\n" +
        "  nodeType: \"OTHER\"\n" +
        "  mgmtIpAddress:\n" +
        "    address: \"" + .private_ip + "\"\n" +
        "  _type: \"NODE\""
      )[]
    ' >> /tmp/nodes.yml
fi

# Add ECGroup nodes if available
if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "$${!ECGROUP_NODES_ARRAY[@]}"; do
        instance_name="$${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}"
        node_ip="$${ECGROUP_NODES_ARRAY[$i]}"
        cat >> /tmp/nodes.yml << NODE_EOF
- name: "$instance_name"
  nodeType: "OTHER"
  mgmtIpAddress:
    address: "$node_ip"
  _type: "NODE"
NODE_EOF
    done
fi

# Log what was created
echo "Created nodes.yml with $STORAGE_COUNT storage instances and $${#ECGROUP_NODES_ARRAY[@]} ECGroup nodes"

# Create share configuration for OCI
echo 'share:
  name: "{{ share_name }}"
  path: "/{{ share_name }}"
  maxShareSize: 0
  alertThreshold: 90
  maxShareSizeType: TB
  smbAliases: []
  exportOptions:
  - subnet: "*"
    rootSquash: false
    accessPermissions: RW
  shareSnapshots: []
  shareObjectives:
  - objective:
      name: no-atime
    applicability: "TRUE"
  - objective:
      name: confine-to-{{ volume_group_name }}
    applicability: "TRUE"
  smbBrowsable: true
  shareSizeLimit: 0
  oci_optimized: true' > /tmp/share.yml

# Create ECGroup configuration for OCI
cat <<EOF > /tmp/ecgroup.yml
- name: Configure ECGroup from the OCI controller node
  hosts: all
  gather_facts: false
  vars:
    ecgroup_name: ecg
    ansible_user: $ANSIBLE_USER
    ansible_ssh_private_key_file: ${ANSIBLE_HOME}/.ssh/ansible_admin_key
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60"
  become: true
  tasks:
    - name: Create the cluster on OCI
      shell: >
        /opt/rozofs-installer/rozo_rozofs_create.sh -n {{ ecgroup_name }} -s "${ECGROUP_NODES}" -t external -d 3
      register: create_cluster_result

    - name: Add CTDB nodes for OCI
      shell: >
        /opt/rozofs-installer/rozo_rozofs_ctdb_node_add.sh -n {{ ecgroup_name }} -c "${ECGROUP_NODES}"
      register: ctdb_node_add_result

    - name: Setup DRBD on OCI block storage
      shell: >
        /opt/rozofs-installer/rozo_drbd.sh -y -n {{ ecgroup_name }} -d "${ECGROUP_METADATA_ARRAY}"
      register: drbd_result

    - name: Create the array on OCI
      shell: >
        /opt/rozofs-installer/rozo_compute_cluster_balanced.sh -y -n {{ ecgroup_name }} -d "${ECGROUP_STORAGE_ARRAY}"
      register: compute_cluster_result

    - name: Propagate the configuration
      shell: >
        /opt/rozofs-installer/rozo_rozofs_install.sh -n {{ ecgroup_name }}
      register: install_result
  run_once: true
EOF

# Write the Ansible playbook for SSH key distribution (OCI optimized)
PLAYBOOK_FILE="${ANSIBLE_HOME}/distribute_keys.yml"
cat > "$PLAYBOOK_FILE" << EOF
---
# Play 1: Generate keys on all OCI hosts and gather their public keys
- name: Gather Host Keys from OCI Instances
  hosts: all_nodes
  gather_facts: false
  vars:
    ansible_user: $ANSIBLE_USER
    ansible_ssh_private_key_file: ${ANSIBLE_HOME}/.ssh/ansible_admin_key
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60"

  tasks:
    - name: Ensure .ssh directory exists for user $ANSIBLE_USER
      become: true
      file:
        path: "${ANSIBLE_HOME}/.ssh"
        state: directory
        owner: $ANSIBLE_USER
        group: $ANSIBLE_USER
        mode: '0700'

    - name: Ensure SSH key pair exists for each OCI host
      become: true
      community.crypto.openssh_keypair:
        path: ${ANSIBLE_HOME}/.ssh/id_rsa
        owner: $ANSIBLE_USER
        group: $ANSIBLE_USER
        mode: '0600'
        type: rsa
        size: 2048

    - name: Fetch the public key content from each OCI host
      slurp:
        src: ${ANSIBLE_HOME}/.ssh/id_rsa.pub
      register: host_public_key

# Play 2: Distribute all collected public keys to all OCI hosts
- name: Distribute All Keys to OCI Instances
  hosts: all_nodes
  gather_facts: false
  vars:
    ansible_user: $ANSIBLE_USER
    ansible_ssh_private_key_file: ${ANSIBLE_HOME}/.ssh/ansible_admin_key
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60"

  tasks:
    - name: Add each host's public key to every other host's authorized_keys file
      authorized_key:
        user: $ANSIBLE_USER
        state: present
        key: "{{ hostvars[item].host_public_key.content | b64decode }}"
      loop: "{{ ansible_play_hosts_all }}"
EOF

chown $ANSIBLE_USER:$ANSIBLE_USER "$PLAYBOOK_FILE"

# ssh-keyscan for OCI instances (with retries and timeouts)
echo "Scanning OCI hosts to populate known_hosts..."
sudo -u $ANSIBLE_USER bash -c "
    timeout 300 ssh-keyscan -H -f ${ANSIBLE_HOME}/inventory.ini >> ${ANSIBLE_HOME}/.ssh/known_hosts 2>/dev/null || {
        echo 'Warning: Some hosts may not be reachable for SSH key scanning'
        # Continue anyway - Ansible will handle host key checking
    }
"

#############################################################################
# Execute Modular Ansible Job Scripts
#############################################################################

echo "Executing modular Ansible job scripts..."

# Execute job scripts in sequence if we have Hammerspace configured
if [ -n "${MGMT_IP}" ]; then
    echo "==> Step 1: Adding storage nodes..."
    sudo /usr/local/ansible/jobs/20-add-storage-nodes.sh || {
        echo "Warning: Storage node addition failed or no new nodes to add"
    }

    echo "==> Step 2: Managing volume groups..."
    sudo /usr/local/ansible/jobs/21-add-volume-groups.sh || {
        echo "Warning: Volume group management failed or no changes needed"
    }

    echo "Hammerspace storage configuration complete"
else
    echo "No Hammerspace management IP configured, skipping storage configuration"
fi

# Handle ECGroup configuration for OCI using modular script
if [ -n "${ECGROUP_INSTANCES}" ]; then
    echo "==> Step 3: Configuring ECGroup cluster..."
    echo "INSTANCES :${ECGROUP_INSTANCES}"
    echo "NODES     :${ECGROUP_NODES}"
    echo "METADATA  :${ECGROUP_METADATA_ARRAY}"
    echo "STORAGE   :${ECGROUP_STORAGE_ARRAY}"

    # Execute ECGroup configuration script
    sudo /usr/local/ansible/jobs/30-configure-ecgroup.sh || {
        echo "Warning: ECGroup configuration failed or no new nodes to configure"
    }

    echo "ECGroup configuration complete"
else
    echo "No ECGroup instances configured, skipping ECGroup setup"
fi

# Run the Ansible playbook to distribute the SSH keys
echo "Running Ansible playbook to distribute SSH keys across OCI instances..."
sudo -u $ANSIBLE_USER bash -c "ansible-playbook -i ${ANSIBLE_HOME}/inventory.ini ${ANSIBLE_HOME}/distribute_keys.yml"

# Create OCI-specific status and information file
cat > ${ANSIBLE_HOME}/oci-ansible-status.txt << EOF
=== OCI Ansible Controller Status ===
Date: $(date)
Ansible User: $ANSIBLE_USER
OS Type: $OS_TYPE
OCI Region: $${OCI_REGION:-"Not specified"}
OCI Compartment: $${OCI_COMPARTMENT_ID:-"Not specified"}

=== Configuration Files ===
- Inventory: ${ANSIBLE_HOME}/inventory.ini
- Config: ${ANSIBLE_HOME}/ansible.cfg
- SSH Key: ${ANSIBLE_HOME}/.ssh/ansible_admin_key
- Key Distribution Playbook: ${ANSIBLE_HOME}/distribute_keys.yml

=== Ansible Version ===
$(ansible --version)

=== Target Nodes ===
$(cat ${ANSIBLE_HOME}/inventory.ini)

=== SSH Key Status ===
SSH key configured: $([ -f "${ANSIBLE_HOME}/.ssh/ansible_admin_key" ] && echo "Yes" || echo "No")
Key permissions: $(ls -la ${ANSIBLE_HOME}/.ssh/ansible_admin_key 2>/dev/null || echo "Key not found")

=== Hammerspace Configuration ===
Management IP: $${MGMT_IP:-"Not configured"}
Volume Group: $${VG_NAME:-"Not specified"}
Share Name: $${SHARE_NAME:-"Not specified"}

=== ECGroup Configuration ===
ECGroup Instances: $${ECGROUP_INSTANCES:-"None"}
ECGroup Nodes: $${ECGROUP_NODES:-"None"}

=== Modular Job Scripts ===
Job Scripts Location: /usr/local/ansible/jobs/
Function Library: /usr/local/lib/ansible_functions.sh
Inventory File: /var/ansible/trigger/inventory.ini
State Tracking: /var/run/ansible_jobs_status/

Available Scripts:
$(ls -la /usr/local/ansible/jobs/ 2>/dev/null || echo "Scripts not deployed")

=== Next Steps ===
1. Run 'ansible all -m ping' to test connectivity
2. Check /var/log/ansible.log for detailed logs
3. Use 'ansible-playbook' to run additional configurations
EOF

chown $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/oci-ansible-status.txt

echo "=== OCI Ansible Configuration Complete ==="
echo "Ansible configured for Oracle Cloud Infrastructure"
echo "Ansible user: $ANSIBLE_USER"
echo "Configuration summary: ${ANSIBLE_HOME}/oci-ansible-status.txt"
echo "SSH key distribution completed across OCI instances"