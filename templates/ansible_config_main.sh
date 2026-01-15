#!/bin/bash
# Ansible Main Configuration Script
# This script is uploaded via null_resource provisioner after instance creation
# It sources variables from /var/ansible/deployment_vars.sh created by bootstrap
set -euo pipefail

echo "=========================================="
echo "Ansible Main Configuration Starting..."
echo "=========================================="

# Source deployment variables created by bootstrap script
if [ -f /var/ansible/deployment_vars.sh ]; then
    source /var/ansible/deployment_vars.sh
    echo "✓ Loaded deployment variables"
else
    echo "✗ ERROR: /var/ansible/deployment_vars.sh not found!"
    echo "Bootstrap script may have failed"
    exit 1
fi

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

# Ansible job scripts are uploaded by null_resource provisioner before this script runs
# Verify they exist
echo "Verifying ansible job scripts..."
if [ ! -f /usr/local/ansible/jobs/20-configure-ecgroup.sh ]; then
    echo "⚠ WARNING: Ansible job scripts not found in /usr/local/ansible/jobs/"
    echo "null_resource provisioner may have failed to upload scripts"
    echo "Attempting to download from GitHub as fallback..."

    sudo wget -O /usr/local/lib/ansible_functions.sh \
      https://raw.githubusercontent.com/hammerspace-solutions/Terraform-OCI/main/modules/ansible/ansible_job_files/ansible_functions.sh || true
    sudo chmod +x /usr/local/lib/ansible_functions.sh

    for script in 20-configure-ecgroup.sh 30-add-storage-nodes.sh 32-add-storage-volumes.sh 33-add-storage-volume-group.sh 34-create-storage-share.sh 35-add-ecgroup-volumes.sh 36-add-ecgroup-volume-group.sh 37-create-ecgroup-share.sh; do
      sudo wget -O /usr/local/ansible/jobs/$script \
        https://raw.githubusercontent.com/hammerspace-solutions/Terraform-OCI/main/modules/ansible/ansible_job_files/$script || true
      sudo chmod +x /usr/local/ansible/jobs/$script
    done
else
    echo "✓ Ansible job scripts found - uploaded by provisioner"
fi

# These variables are already loaded from /var/ansible/deployment_vars.sh
# Just create arrays from them
ECGROUP_INSTANCES_ARRAY=($ECGROUP_INSTANCES)
ECGROUP_NODES_ARRAY=($ECGROUP_NODES)
STORAGE_COUNT=$(echo "$STORAGE_INSTANCES" | jq '. | length' 2>/dev/null || echo "0")

cat > /var/ansible/trigger/inventory.ini << INV_EOF
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
    echo "$STORAGE_INSTANCES" | jq -r '.[] | .private_ip + " node_name=\"" + .name + "\""' >> /var/ansible/trigger/inventory.ini
fi

echo "" >> /var/ansible/trigger/inventory.ini
echo "[ecgroup_nodes]" >> /var/ansible/trigger/inventory.ini
if [ ${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "${!ECGROUP_NODES_ARRAY[@]}"; do
        echo "${ECGROUP_NODES_ARRAY[$i]} node_name=\"${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}\" ansible_user=rocky" >> /var/ansible/trigger/inventory.ini
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
    echo "$STORAGE_INSTANCES" | jq -r 'map("- name: \"" + .name + "\"\n  nodeType: \"OTHER\"\n  mgmtIpAddress:\n    address: \"" + .private_ip + "\"\n  _type: \"NODE\"")[]' >> /tmp/nodes.yml
fi

if [ ${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    for i in "${!ECGROUP_NODES_ARRAY[@]}"; do
        cat >> /tmp/nodes.yml << NODE_EOF
- name: "${ECGROUP_INSTANCES_ARRAY[$i]:-ecgroup-node-$i}"
  nodeType: "OTHER"
  mgmtIpAddress:
    address: "${ECGROUP_NODES_ARRAY[$i]}"
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
if [ ${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
    echo "=========================================="
    echo "Distributing root SSH keys for ECGroup nodes..."
    echo "=========================================="

    # Step 1: Generate root SSH keys on each ECGroup node
    echo "Generating root SSH keys on each node..."
    for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
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
    for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
        echo "  - Collecting key from $node_ip"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo cat /root/.ssh/id_rsa.pub" >> "$root_pubkeys_file" 2>/dev/null || {
            echo "WARNING: Failed to collect root public key from $node_ip"
        }
    done

    # Step 3: Distribute all root public keys to all ECGroup nodes
    echo "Distributing all root public keys to all nodes..."
    for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
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
    for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
            -i ${ANSIBLE_HOME}/.ssh/ansible_admin_key rocky@$node_ip \
            "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
             sudo systemctl reload sshd" || {
            echo "WARNING: Failed to configure sshd on $node_ip"
        }
    done

    # Step 5: Test root SSH connectivity
    echo "Testing root SSH connectivity between nodes..."
    first_node="${ECGROUP_NODES_ARRAY[0]}"
    ssh_test_passed=true
    for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
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
    if [ ${#ECGROUP_NODES_ARRAY[@]} -gt 0 ]; then
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
            total_nodes=${#ECGROUP_NODES_ARRAY[@]}

            for node_ip in "${ECGROUP_NODES_ARRAY[@]}"; do
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
            first_node="${ECGROUP_NODES_ARRAY[0]}"
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

# Only run storage server jobs if ADD_STORAGE_SERVER_VOLUMES is true and we have storage servers
if [ -n "${MGMT_IP}" ] && [ "${ADD_STORAGE_SERVER_VOLUMES}" = "true" ] && [ "$STORAGE_COUNT" -gt 0 ]; then
    echo "=========================================="
    echo "Configuring Storage Servers..."
    echo "=========================================="

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
    storage_ips=$(echo "$STORAGE_INSTANCES" | jq -r '.[].private_ip' 2>/dev/null || echo "")

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
elif [ -n "${MGMT_IP}" ]; then
    echo "=========================================="
    echo "Skipping Storage Server configuration (not enabled or no storage servers)"
    echo "  ADD_STORAGE_SERVER_VOLUMES=${ADD_STORAGE_SERVER_VOLUMES}"
    echo "  STORAGE_COUNT=${STORAGE_COUNT}"
    echo "=========================================="
fi

# Only run ECGroup jobs if ECGROUP_ADD_TO_HAMMERSPACE is true and we have ECGroup nodes
if [ -n "${MGMT_IP}" ] && [ "${ECGROUP_ADD_TO_HAMMERSPACE}" = "true" ] && [ -n "${ECGROUP_INSTANCES}" ]; then
    echo "=========================================="
    echo "Configuring ECGroup integration with Hammerspace..."
    echo "=========================================="

    run_ansible_job "35-add-ecgroup-volumes.sh" || echo "WARNING: ECGroup volume addition failed"
    run_ansible_job "36-add-ecgroup-volume-group.sh" || echo "WARNING: ECGroup volume group creation failed"
    run_ansible_job "37-create-ecgroup-share.sh" || echo "WARNING: ECGroup share creation failed"
elif [ -n "${MGMT_IP}" ]; then
    echo "=========================================="
    echo "Skipping ECGroup Hammerspace integration (not enabled or no ECGroup nodes)"
    echo "  ECGROUP_ADD_TO_HAMMERSPACE=${ECGROUP_ADD_TO_HAMMERSPACE}"
    echo "  ECGROUP_INSTANCES=${ECGROUP_INSTANCES}"
    echo "=========================================="
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
