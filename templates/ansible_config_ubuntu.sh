#!/bin/bash
set -euo pipefail
TARGET_NODES_JSON='${TARGET_NODES_JSON}'
ADMIN_PRIVATE_KEY='${ADMIN_PRIVATE_KEY}'

retry_apt() {
    local max_attempts=5
    for i in $(seq 1 $max_attempts); do
        "$@" && return 0
        sleep 10
    done
    return 1
}

if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    PKG_MGR="dnf"
    command -v dnf &> /dev/null || PKG_MGR="yum"
    OS_TYPE="oracle"
    sudo $PKG_MGR -y update
    sudo $PKG_MGR -y install epel-release || true
    sudo $PKG_MGR install -y python3-pip git bc screen net-tools wget curl
    sudo $PKG_MGR install -y ansible python3-jq || sudo python3 -m pip install ansible jq
    command -v jq &> /dev/null || sudo python3 -m pip install jq
else
    OS_TYPE="debian"
    retry_apt sudo apt-get -y update
    retry_apt sudo apt-get install -y python3-pip git bc screen net-tools wget curl software-properties-common
    retry_apt sudo add-apt-repository --yes --update ppa:ansible/ansible
    retry_apt sudo apt-get install -y ansible jq
fi

if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y upgrade || true
else
    retry_apt sudo apt-get -y upgrade || true
fi

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"

if [ -z "$TARGET_USER" ]; then
    if [ "$OS_TYPE" = "oracle" ]; then
        TARGET_USER="opc"
        TARGET_HOME="/home/opc"
    else
        TARGET_USER="ubuntu"
        TARGET_HOME="/home/ubuntu"
    fi
fi

sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF

sudo mkdir -p /mnt/nfs-test /mnt/hammerspace
sudo chmod 777 /mnt/nfs-test /mnt/hammerspace

if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "${TARGET_HOME}/.ssh"
    chmod 700 "${TARGET_HOME}/.ssh"
    touch "${TARGET_HOME}/.ssh/authorized_keys"
    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" "${TARGET_HOME}/.ssh/authorized_keys"; then
            echo "$key" >> "${TARGET_HOME}/.ssh/authorized_keys"
        fi
    done
    chmod 600 "${TARGET_HOME}/.ssh/authorized_keys"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.ssh"
fi

if [ "$TARGET_USER" = "ubuntu" ]; then
    sudo -u ubuntu ansible-galaxy collection install community.crypto || true
else
    sudo -u $TARGET_USER ansible-galaxy collection install community.crypto || true
fi

ANSIBLE_USER=$TARGET_USER
ANSIBLE_HOME=$TARGET_HOME

INVENTORY_FILE="${ANSIBLE_HOME}/inventory.ini"
echo "[all_nodes]" > "$INVENTORY_FILE"
echo "$TARGET_NODES_JSON" | jq -r '.[] | .private_ip' >> "$INVENTORY_FILE"
chown $ANSIBLE_USER:$ANSIBLE_USER "$INVENTORY_FILE"

PRIVATE_KEY_FILE="${ANSIBLE_HOME}/.ssh/ansible_admin_key"
mkdir -p ${ANSIBLE_HOME}/.ssh
echo "$ADMIN_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
chown -R $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/.ssh

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

sudo mkdir -p /usr/local/ansible/jobs /usr/local/lib /var/run/ansible_jobs_status /var/ansible/trigger

# Download ansible scripts from GitHub
# NOTE: These will be replaced by local versions via null_resource provisioner after instance creation
# This ensures fresh deployments start with working scripts from GitHub,
# then get updated with local fixes automatically
sudo wget -O /usr/local/lib/ansible_functions.sh \
  https://raw.githubusercontent.com/hammerspace-solutions/Terraform-OCI/main/modules/ansible/ansible_job_files/ansible_functions.sh || \
  curl -o /usr/local/lib/ansible_functions.sh \
  https://raw.githubusercontent.com/hammerspace-solutions/Terraform-AWS/main/modules/ansible/ansible_job_files/ansible_functions.sh
sudo chmod +x /usr/local/lib/ansible_functions.sh

for script in 20-configure-ecgroup.sh 30-add-storage-nodes.sh 32-add-storage-volumes.sh 33-add-storage-volume-group.sh 34-create-storage-share.sh 35-add-ecgroup-volumes.sh 36-add-ecgroup-volume-group.sh 37-create-ecgroup-share.sh; do
  sudo wget -O /usr/local/ansible/jobs/$script \
    https://raw.githubusercontent.com/hammerspace-solutions/Terraform-OCI/main/modules/ansible/ansible_job_files/$script || \
    curl -o /usr/local/ansible/jobs/$script \
    https://raw.githubusercontent.com/hammerspace-solutions/Terraform-AWS/main/modules/ansible/ansible_job_files/$script
  sudo chmod +x /usr/local/ansible/jobs/$script
done

ECGROUP_INSTANCES="${ECGROUP_INSTANCES}"
ECGROUP_NODES="${ECGROUP_NODES}"
ECGROUP_METADATA_ARRAY="${ECGROUP_METADATA_ARRAY}"
ECGROUP_STORAGE_ARRAY="${ECGROUP_STORAGE_ARRAY}"
STORAGE_COUNT=$(echo '${STORAGE_INSTANCES}' | jq '. | length')
ECGROUP_INSTANCES_ARRAY=($ECGROUP_INSTANCES)
ECGROUP_NODES_ARRAY=($ECGROUP_NODES)

cat > /var/ansible/trigger/inventory.ini << 'INV_EOF'
[all:vars]
hs_username = admin
hs_password = ${ADMIN_USER_PASSWORD}
volume_group_name = ${VG_NAME}
share_name = ${SHARE_NAME}
ecgroup_add_to_hammerspace = ${ECGROUP_ADD_TO_HAMMERSPACE}
ecgroup_volume_group_name = ${ECGROUP_VG_NAME}
ecgroup_share_name = ${ECGROUP_SHARE_NAME}
add_storage_server_volumes = ${ADD_STORAGE_SERVER_VOLUMES}
add_ecgroup_volumes = ${ADD_ECGROUP_VOLUMES}
ecgroup_metadata_array = ${ECGROUP_METADATA_ARRAY}
ecgroup_storage_array = ${ECGROUP_STORAGE_ARRAY}

[hammerspace]
INV_EOF

# Add Hammerspace/Anvil IPs if available
if [ -n "${MGMT_IP}" ]; then
    echo "${MGMT_IP}" >> /var/ansible/trigger/inventory.ini
fi

echo "" >> /var/ansible/trigger/inventory.ini
echo "[storage_servers]" >> /var/ansible/trigger/inventory.ini
if [ "$STORAGE_COUNT" -gt 0 ]; then
    echo '${STORAGE_INSTANCES}' | jq -r '.[] | .private_ip + " node_name=\"" + .name + "\""' >> /var/ansible/trigger/inventory.ini
fi

echo "" >> /var/ansible/trigger/inventory.ini
echo "[ecgroup_nodes]" >> /var/ansible/trigger/inventory.ini
if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "$${!ECGROUP_NODES_ARRAY[@]}"; do
        echo "$${ECGROUP_NODES_ARRAY[$i]} node_name=\"$${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}\" ansible_user=debian" >> /var/ansible/trigger/inventory.ini
    done
fi

cat > /tmp/anvil.yml << EOF
data_cluster_mgmt_ip: "${MGMT_IP}"
hsuser: admin
password: "${ADMIN_USER_PASSWORD}"
volume_group_name: "${VG_NAME}"
share_name: "${SHARE_NAME}"
oci_environment: true
EOF

echo "storages:" > /tmp/nodes.yml
if [ "$STORAGE_COUNT" -gt 0 ]; then
    echo '${STORAGE_INSTANCES}' | jq -r 'map("- name: \"" + .name + "\"\n  nodeType: \"OTHER\"\n  mgmtIpAddress:\n    address: \"" + .private_ip + "\"\n  _type: \"NODE\"")[]' >> /tmp/nodes.yml
fi

if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "$${!ECGROUP_NODES_ARRAY[@]}"; do
        cat >> /tmp/nodes.yml << NODE_EOF
- name: "$${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}"
  nodeType: "OTHER"
  mgmtIpAddress:
    address: "$${ECGROUP_NODES_ARRAY[$i]}"
  _type: "NODE"
NODE_EOF
    done
fi

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
    ansible_user: debian
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

sudo -u $ANSIBLE_USER bash -c "timeout 300 ssh-keyscan -H -f ${ANSIBLE_HOME}/inventory.ini >> ${ANSIBLE_HOME}/.ssh/known_hosts 2>/dev/null || true"

if [ -n "${ECGROUP_INSTANCES}" ]; then
    sudo /usr/local/ansible/jobs/20-configure-ecgroup.sh || true
fi

if [ -n "${MGMT_IP}" ]; then
    sudo /usr/local/ansible/jobs/30-add-storage-nodes.sh || true

    # Wait for storage nodes to fully initialize their volumes before adding them
    echo "Waiting for storage nodes to initialize volumes..."
    sleep 30

    sudo /usr/local/ansible/jobs/32-add-storage-volumes.sh || true
    sudo /usr/local/ansible/jobs/33-add-storage-volume-group.sh || true
    sudo /usr/local/ansible/jobs/34-create-storage-share.sh || true
    sudo /usr/local/ansible/jobs/35-add-ecgroup-volumes.sh || true
    sudo /usr/local/ansible/jobs/36-add-ecgroup-volume-group.sh || true
    sudo /usr/local/ansible/jobs/37-create-ecgroup-share.sh || true
fi

sudo -u $ANSIBLE_USER bash -c "ansible-playbook -i ${ANSIBLE_HOME}/inventory.ini ${ANSIBLE_HOME}/distribute_keys.yml"

cat > ${ANSIBLE_HOME}/oci-status.txt << EOF
Date: $(date)
User: $ANSIBLE_USER
Inventory: ${ANSIBLE_HOME}/inventory.ini
Job Scripts: /usr/local/ansible/jobs/
Trigger Inventory: /var/ansible/trigger/inventory.ini
EOF

chown $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/oci-status.txt