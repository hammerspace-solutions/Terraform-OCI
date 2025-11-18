#!/bin/bash

# OCI ECGroup Node Configuration Script
# Updated for Oracle Cloud Infrastructure compatibility

# Terraform-provided variables (single $ for Terraform interpolation)
SSH_KEYS="${SSH_KEYS}"

set -euo pipefail
shopt -s failglob

# Detect OS and set package manager
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    # Oracle Linux or RHEL-based
    PKG_MGR="dnf"
    if ! command -v dnf &> /dev/null; then
        PKG_MGR="yum"
    fi
    OS_TYPE="oracle"
elif [ -f /etc/debian_version ]; then
    # Ubuntu/Debian
    PKG_MGR="apt"
    OS_TYPE="debian"
else
    echo "Unsupported OS detected"
    exit 1
fi

# Update system packages
echo "Updating system packages..."
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y update
    sudo $PKG_MGR -y install epel-release || true
    sudo $PKG_MGR -y install net-tools wget curl bind-utils
else
    sudo apt-get -y update
    sudo apt-get -y install net-tools wget curl dnsutils
fi

# Configure SSH settings for OCI
echo "Configuring SSH settings for OCI..."
sudo tee -a /etc/ssh/ssh_config > /dev/null <<'EOF'
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF

# OCI-specific network configuration
echo "Configuring OCI-specific network settings..."
if [ "$OS_TYPE" = "oracle" ]; then
    # Ensure NetworkManager is properly configured for OCI
    sudo systemctl enable NetworkManager
    sudo systemctl start NetworkManager
fi

# Configure firewall for OCI ECGroup requirements
echo "Configuring firewall for ECGroup..."
if [ "$OS_TYPE" = "oracle" ]; then
    # Configure firewalld for Oracle Linux
    sudo systemctl enable firewalld
    sudo systemctl start firewalld
    
    # Open required ports for ECGroup
    sudo firewall-cmd --permanent --add-port=22/tcp
    sudo firewall-cmd --permanent --add-port=873/tcp
    sudo firewall-cmd --permanent --add-port=9090/tcp
    sudo firewall-cmd --permanent --add-port=50000-51000/tcp
    sudo firewall-cmd --reload
else
    # Configure ufw for Ubuntu/Debian
    if command -v ufw &> /dev/null; then
        sudo ufw allow 22/tcp
        sudo ufw allow 873/tcp
        sudo ufw allow 9090/tcp
        sudo ufw allow 50000:51000/tcp
        sudo ufw --force enable
    else
        echo "ufw not available on this system, skipping firewall configuration"
    fi
fi

# SSH Key Management for OCI
echo "Managing SSH keys for OCI..."
TARGET_USER="opc"  # Default OCI user for Oracle Linux
if [ "$OS_TYPE" = "debian" ]; then
    TARGET_USER="ubuntu"
elif [ -f /etc/rocky-release ]; then
    TARGET_USER="rocky"  # Rocky Linux uses 'rocky' user
fi

TARGET_HOME="/home/$TARGET_USER"

if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "$TARGET_HOME/.ssh"
    chmod 700 "$TARGET_HOME/.ssh"
    touch "$TARGET_HOME/.ssh/authorized_keys"

    # Process keys line by line
    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" "$TARGET_HOME/.ssh/authorized_keys"; then
            echo "$key" >> "$TARGET_HOME/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
fi

# Create admin user for ECGroup if it doesn't exist
if ! id "admin" &>/dev/null; then
    echo "Creating admin user for ECGroup..."
    sudo useradd -m -s /bin/bash admin
    echo "admin ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/admin
    
    # Copy SSH keys to admin user
    if [ -n "${SSH_KEYS}" ]; then
        sudo mkdir -p "/home/admin/.ssh"
        sudo chmod 700 "/home/admin/.ssh"
        sudo touch "/home/admin/.ssh/authorized_keys"

        echo "${SSH_KEYS}" | while read -r key; do
            if [ -n "$key" ] && ! sudo grep -qF "$key" "/home/admin/.ssh/authorized_keys"; then
                echo "$key" | sudo tee -a "/home/admin/.ssh/authorized_keys" > /dev/null
            fi
        done

        sudo chmod 600 "/home/admin/.ssh/authorized_keys"
        sudo chown -R "admin:admin" "/home/admin/.ssh"
    fi
fi

# OCI-specific optimizations
echo "Applying OCI-specific optimizations..."

# Configure kernel parameters for OCI
sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'
# OCI Network optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.core.netdev_max_backlog = 5000
EOF

# Apply sysctl changes
sudo sysctl -p

# Configure OCI instance metadata service access
echo "Configuring OCI instance metadata access..."
sudo tee /etc/systemd/system/oci-metadata.service > /dev/null <<'EOF'
[Unit]
Description=OCI Instance Metadata Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/ > /var/log/oci-instance-metadata.log'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable oci-metadata.service

# Log completion
echo "OCI ECGroup node configuration completed successfully"
echo "Instance configured for OCI environment with ECGroup requirements"
echo "Target user: $TARGET_USER"
echo "Admin user created: admin"

# Final system update and cleanup
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y upgrade
    sudo $PKG_MGR clean all
else
    sudo apt-get -y upgrade
    sudo apt-get autoremove -y
    sudo apt-get autoclean
fi

echo "OCI ECGroup node setup complete. System ready for ECGroup installation."