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

sudo mkdir -p /usr/local/ansible/jobs /usr/local/lib /var/run/ansible_jobs_status /var/ansible/trigger /var/log/ansible_jobs

# Enhanced logging function for ansible jobs
run_ansible_job() {
    local script_name=$1
    local script_path="/usr/local/ansible/jobs/$script_name"
    local log_dir="/var/log/ansible_jobs"
    local log_file="$log_dir/$script_name.log"
    local status_file="$log_dir/$script_name.status"

    if [ ! -f "$script_path" ]; then
        echo "⚠ WARNING: Script $script_name not found at $script_path" | tee -a "$log_file"
        return 1
    fi

    echo "========================================" | tee -a "$log_file"
    echo "Running: $script_name" | tee -a "$log_file"
    echo "Started: $(date)" | tee -a "$log_file"
    echo "========================================" | tee -a "$log_file"

    if sudo "$script_path" >> "$log_file" 2>&1; then
        local exit_code=0
        echo "========================================" | tee -a "$log_file"
        echo "✓ $script_name completed successfully" | tee -a "$log_file"
        echo "Finished: $(date)" | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        echo "SUCCESS" > "$status_file"
        return 0
    else
        local exit_code=$?
        echo "========================================" | tee -a "$log_file"
        echo "✗ $script_name failed with exit code $exit_code" | tee -a "$log_file"
        echo "Finished: $(date)" | tee -a "$log_file"
        echo "Log file: $log_file" | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        echo "FAILED (exit code: $exit_code)" > "$status_file"
        return $exit_code
    fi
}

# Print summary of ansible job execution
print_ansible_jobs_summary() {
    local log_dir="/var/log/ansible_jobs"

    echo ""
    echo "=========================================="
    echo "Ansible Jobs Execution Summary"
    echo "=========================================="

    if [ -d "$log_dir" ] && [ "$(ls -A $log_dir/*.status 2>/dev/null)" ]; then
        for status_file in $log_dir/*.status; do
            local script_name=$(basename "$status_file" .status)
            local status=$(cat "$status_file")
            local log_file="$log_dir/$script_name.log"

            if [[ "$status" == "SUCCESS" ]]; then
                echo "  ✓ $script_name - $status"
            else
                echo "  ✗ $script_name - $status"
                echo "    Log: $log_file"
            fi
        done
    else
        echo "  No ansible jobs were executed"
    fi

    echo "=========================================="
    echo "Detailed logs available in: $log_dir/"
    echo "=========================================="
    echo ""
}

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
        echo "$${ECGROUP_NODES_ARRAY[$i]} node_name=\"$${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}\" ansible_user=rocky" >> /var/ansible/trigger/inventory.ini
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
    ansible_user: rocky
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

# Distribute root SSH keys for ECGroup nodes (required for RozoFS cluster configuration)
if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    echo "=========================================="
    echo "Distributing root SSH keys for ECGroup nodes..."
    echo "=========================================="

    # Step 1: Generate root SSH keys on each ECGroup node
    echo "Generating root SSH keys on each node..."
    for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
        echo "  - Generating key on $node_ip"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo mkdir -p /root/.ssh && \
             sudo chmod 700 /root/.ssh && \
             sudo ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N '' -q || true" || {
            echo "WARNING: Failed to generate root SSH key on $node_ip"
        }
    done

    # Step 2: Collect all root public keys
    echo "Collecting root public keys from all nodes..."
    root_pubkeys_file=$(mktemp)
    for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
        echo "  - Collecting key from $node_ip"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo cat /root/.ssh/id_rsa.pub" >> "$root_pubkeys_file" 2>/dev/null || {
            echo "WARNING: Failed to collect root public key from $node_ip"
        }
    done

    # Step 3: Distribute all root public keys to all ECGroup nodes
    echo "Distributing all root public keys to all nodes..."
    for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
        echo "  - Distributing keys to $node_ip"
        cat "$root_pubkeys_file" | ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo tee -a /root/.ssh/authorized_keys > /dev/null && \
             sudo sort -u /root/.ssh/authorized_keys | sudo tee /root/.ssh/authorized_keys.tmp > /dev/null && \
             sudo mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys && \
             sudo chmod 600 /root/.ssh/authorized_keys && \
             sudo chmod 700 /root/.ssh" || {
            echo "WARNING: Failed to distribute root SSH keys to $node_ip"
        }
    done

    # Step 4: Enable root login with public key authentication
    echo "Configuring SSH to allow root login with keys..."
    for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
             sudo systemctl reload sshd" || {
            echo "WARNING: Failed to configure sshd on $node_ip"
        }
    done

    # Step 5: Test root SSH connectivity
    echo "Testing root SSH connectivity between nodes..."
    first_node="$${ECGROUP_NODES_ARRAY[0]}"
    ssh_test_passed=true
    for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
        echo "  - Testing root SSH from $first_node to $node_ip"
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$first_node \
            "sudo ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$node_ip hostname" > /dev/null 2>&1; then
            echo "    ✓ Success"
        else
            echo "    ✗ Failed"
            ssh_test_passed=false
        fi
    done

    # Cleanup
    rm -f "$root_pubkeys_file"

    if [ "$ssh_test_passed" = true ]; then
        echo "=========================================="
        echo "✓ Root SSH key distribution completed successfully"
        echo "=========================================="
    else
        echo "=========================================="
        echo "⚠ Root SSH key distribution completed with warnings"
        echo "  Some nodes may not have proper root SSH access"
        echo "  ECGroup RozoFS configuration may fail"
        echo "=========================================="
    fi
fi

if [ -n "${ECGROUP_INSTANCES}" ]; then
    run_ansible_job "20-configure-ecgroup.sh" || echo "WARNING: ECGroup configuration failed, check logs"

    # Wait for ECGroup RozoFS services to be fully ready
    if [ $${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
        echo "=========================================="
        echo "Waiting for ECGroup RozoFS services to start..."
        echo "=========================================="

        max_wait=600  # 10 minutes total timeout
        check_interval=15
        elapsed=0
        all_ready=false

        while [ $elapsed -lt $max_wait ]; do
            echo "Checking ECGroup service health... ($elapsed/$max_wait seconds)"

            ready_count=0
            total_nodes=$${#ECGROUP_NODES_ARRAY[@]}

            for node_ip in "$${ECGROUP_NODES_ARRAY[@]}"; do
                # Check if both storage and export services are active
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                    -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
                    "systemctl is-active --quiet rozofs-storaged && systemctl is-active --quiet rozofs-exportd" 2>/dev/null; then
                    echo "  ✓ $node_ip - RozoFS services active"
                    ready_count=$((ready_count + 1))
                else
                    echo "  ⏳ $node_ip - Waiting for RozoFS services..."
                fi
            done

            if [ $ready_count -eq $total_nodes ]; then
                echo "=========================================="
                echo "✓ All $total_nodes ECGroup nodes have RozoFS services running"
                echo "=========================================="
                all_ready=true
                break
            fi

            echo "  $ready_count/$total_nodes nodes ready, waiting..."
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done

        if [ "$all_ready" = false ]; then
            echo "=========================================="
            echo "⚠ WARNING: ECGroup RozoFS services did not start on all nodes within timeout"
            echo "  This may cause ECGroup volume addition to fail"
            echo "  Check /var/log/cloud-init-output.log on ECGroup nodes for errors"
            echo "=========================================="
        else
            # Additional wait for volume initialization after services are up
            echo "Services are up, waiting 30 seconds for volume initialization..."
            sleep 30

            # Verify volumes are available
            echo "Verifying ECGroup volumes are available..."
            first_node="$${ECGROUP_NODES_ARRAY[0]}"
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$first_node \
                "df -h | grep -q rozofs" 2>/dev/null; then
                echo "✓ RozoFS volumes are mounted and accessible"
            else
                echo "⚠ WARNING: RozoFS volumes may not be mounted properly"
            fi
        fi
    fi
fi

if [ -n "${MGMT_IP}" ]; then
    run_ansible_job "30-add-storage-nodes.sh" || echo "WARNING: Storage node addition failed, check logs"

    # Wait for storage nodes to fully initialize their volumes before adding them
    echo "=========================================="
    echo "Waiting for storage server volumes to initialize..."
    echo "=========================================="

    max_wait=300  # 5 minutes
    check_interval=10
    elapsed=0
    volumes_ready=false

    # Parse storage server IPs from JSON
    storage_ips=$(echo '${STORAGE_INSTANCES}' | jq -r '.[].private_ip' 2>/dev/null || echo "")

    if [ -n "$storage_ips" ]; then
        while [ $elapsed -lt $max_wait ]; do
            echo "Checking storage server volumes... ($elapsed/$max_wait seconds)"

            ready_count=0
            total_servers=$(echo "$storage_ips" | wc -l)

            for server_ip in $storage_ips; do
                # Check if storage volumes are mounted
                if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                    -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key ${TARGET_USER}@$server_ip \
                    "df -h | grep -q hsvol" 2>/dev/null; then
                    echo "  ✓ $server_ip - Storage volumes mounted"
                    ready_count=$((ready_count + 1))
                else
                    echo "  ⏳ $server_ip - Waiting for volumes..."
                fi
            done

            if [ $ready_count -eq $total_servers ]; then
                echo "=========================================="
                echo "✓ All $total_servers storage servers have volumes mounted"
                echo "=========================================="
                volumes_ready=true
                break
            fi

            echo "  $ready_count/$total_servers servers ready, waiting..."
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done

        if [ "$volumes_ready" = false ]; then
            echo "=========================================="
            echo "⚠ WARNING: Storage server volumes did not initialize within timeout"
            echo "  Proceeding anyway, but volume addition may fail"
            echo "=========================================="
            # Still add a minimum wait
            sleep 30
        fi
    else
        # Fallback to simple wait if we can't parse storage IPs
        echo "Using fallback 30-second wait..."
        sleep 30
    fi

    run_ansible_job "32-add-storage-volumes.sh" || echo "WARNING: Storage volume addition failed"
    run_ansible_job "33-add-storage-volume-group.sh" || echo "WARNING: Storage volume group creation failed"
    run_ansible_job "34-create-storage-share.sh" || echo "WARNING: Storage share creation failed"
    run_ansible_job "35-add-ecgroup-volumes.sh" || echo "WARNING: ECGroup volume addition failed"
    run_ansible_job "36-add-ecgroup-volume-group.sh" || echo "WARNING: ECGroup volume group creation failed"
    run_ansible_job "37-create-ecgroup-share.sh" || echo "WARNING: ECGroup share creation failed"
fi

# Print execution summary
print_ansible_jobs_summary

sudo -u $ANSIBLE_USER bash -c "ansible-playbook -i ${ANSIBLE_HOME}/inventory.ini ${ANSIBLE_HOME}/distribute_keys.yml"

cat > ${ANSIBLE_HOME}/oci-status.txt << EOF
========================================
OCI Deployment Status
========================================
Date: $(date)
User: $ANSIBLE_USER

Configuration Files:
  - Inventory: ${ANSIBLE_HOME}/inventory.ini
  - Trigger Inventory: /var/ansible/trigger/inventory.ini
  - Ansible Config: ${ANSIBLE_HOME}/ansible.cfg

Scripts:
  - Job Scripts: /usr/local/ansible/jobs/
  - Function Library: /usr/local/lib/ansible_functions.sh

Logs:
  - Cloud-Init: /var/log/cloud-init-output.log
  - Ansible Jobs: /var/log/ansible_jobs/
  - Ansible Main: /var/log/ansible.log

Health Checks:
  - Check storage server volumes: ssh <storage-ip> "df -h | grep hsvol"
  - Check ECGroup services: ssh <ecgroup-ip> "systemctl status rozofs-*"
  - Check ECGroup volumes: ssh <ecgroup-ip> "df -h | grep rozofs"

Troubleshooting:
  1. View ansible job summary: cat /var/log/ansible_jobs/*.status
  2. View specific job log: cat /var/log/ansible_jobs/<script-name>.log
  3. Re-run failed job: sudo /usr/local/ansible/jobs/<script-name>.sh

========================================
EOF

chown $ANSIBLE_USER:$ANSIBLE_USER ${ANSIBLE_HOME}/oci-status.txt

echo ""
echo "=========================================="
echo "✓ Ansible Controller Configuration Complete"
echo "=========================================="
echo "Status file created at: ${ANSIBLE_HOME}/oci-status.txt"
echo ""