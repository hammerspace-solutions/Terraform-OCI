#!/bin/bash
# OCI Ansible Bootstrap Script - Minimal cloud-init script to stay under 32KB limit
# This script installs prerequisites and sets up for the main configuration script
set -euo pipefail

retry_apt() {
    local max_attempts=5
    for i in $(seq 1 $max_attempts); do
        "$@" && return 0
        sleep 10
    done
    return 1
}

# Detect OS and install packages
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

# Upgrade packages
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y upgrade || true
else
    retry_apt sudo apt-get -y upgrade || true
fi

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"

if [ -z "$TARGET_USER" ]; then
    if [ "$OS_TYPE" = "oracle" ]; then
        TARGET_USER="opc"
        TARGET_HOME="/home/opc"
    else
        TARGET_USER="ubuntu"
        TARGET_HOME="/home/ubuntu"
    fi
fi

# Configure SSH
sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF

# Create mountpoints
sudo mkdir -p /mnt/nfs-test /mnt/hammerspace
sudo chmod 777 /mnt/nfs-test /mnt/hammerspace

# Setup SSH keys
SSH_KEYS="${SSH_KEYS}"
if [ -n "$SSH_KEYS" ]; then
    mkdir -p "$TARGET_HOME/.ssh"
    chmod 700 "$TARGET_HOME/.ssh"
    touch "$TARGET_HOME/.ssh/authorized_keys"
    echo "$SSH_KEYS" | while read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" "$TARGET_HOME/.ssh/authorized_keys"; then
            echo "$key" >> "$TARGET_HOME/.ssh/authorized_keys"
        fi
    done
    chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
fi

# Install Ansible collections
if [ "$TARGET_USER" = "ubuntu" ]; then
    sudo -u ubuntu ansible-galaxy collection install community.crypto || true
else
    sudo -u $TARGET_USER ansible-galaxy collection install community.crypto || true
fi

# Create directories for main configuration script
sudo mkdir -p /usr/local/ansible/jobs /usr/local/lib /var/run/ansible_jobs_status /var/ansible/trigger /var/log/ansible_jobs

# Write deployment variables file (will be sourced by main config script)
sudo tee /var/ansible/deployment_vars.sh > /dev/null <<'VAREOF'
TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
ANSIBLE_USER="$TARGET_USER"
ANSIBLE_HOME="$TARGET_HOME"
ADMIN_USER_PASSWORD="${ADMIN_USER_PASSWORD}"
TARGET_NODES_JSON='${TARGET_NODES_JSON}'
ADMIN_PRIVATE_KEY='${ADMIN_PRIVATE_KEY}'
MGMT_IP="${MGMT_IP}"
ANVIL_ID="${ANVIL_ID}"
STORAGE_INSTANCES='${STORAGE_INSTANCES}'
VG_NAME="${VG_NAME}"
SHARE_NAME="${SHARE_NAME}"
ECGROUP_ADD_TO_HAMMERSPACE="${ECGROUP_ADD_TO_HAMMERSPACE}"
ECGROUP_VG_NAME="${ECGROUP_VG_NAME}"
ECGROUP_SHARE_NAME="${ECGROUP_SHARE_NAME}"
ADD_STORAGE_SERVER_VOLUMES="${ADD_STORAGE_SERVER_VOLUMES}"
ADD_ECGROUP_VOLUMES="${ADD_ECGROUP_VOLUMES}"
ECGROUP_INSTANCES="${ECGROUP_INSTANCES}"
ECGROUP_HOSTS="${ECGROUP_HOSTS}"
ECGROUP_NODES="${ECGROUP_NODES}"
ECGROUP_METADATA_ARRAY="${ECGROUP_METADATA_ARRAY}"
ECGROUP_STORAGE_ARRAY="${ECGROUP_STORAGE_ARRAY}"
VAREOF

# Write the private key for Ansible
PRIVATE_KEY_FILE="$TARGET_HOME/.ssh/ansible_admin_key"
mkdir -p $TARGET_HOME/.ssh
echo '${ADMIN_PRIVATE_KEY}' > "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
chown -R $TARGET_USER:$TARGET_USER $TARGET_HOME/.ssh

# Create basic inventory
echo "[all_nodes]" > "$TARGET_HOME/inventory.ini"
echo '${TARGET_NODES_JSON}' | jq -r '.[].private_ip' >> "$TARGET_HOME/inventory.ini"
chown $TARGET_USER:$TARGET_USER "$TARGET_HOME/inventory.ini"

# Create basic ansible.cfg
cat > $TARGET_HOME/ansible.cfg << EOF
[defaults]
host_key_checking = False
remote_user = $TARGET_USER
private_key_file = $TARGET_HOME/.ssh/ansible_admin_key
timeout = 30
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
retry_files_enabled = False
log_path = /var/log/ansible.log

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=60 -o ServerAliveCountMax=3
pipelining = True
EOF

chown $TARGET_USER:$TARGET_USER $TARGET_HOME/ansible.cfg

# Create a marker file to indicate bootstrap is complete
echo "Bootstrap completed at $(date)" | sudo tee /var/ansible/bootstrap_complete.txt

echo "=========================================="
echo "Ansible Bootstrap Complete"
echo "Waiting for main configuration script upload..."
echo "=========================================="
