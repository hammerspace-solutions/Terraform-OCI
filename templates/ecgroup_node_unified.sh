#!/bin/bash

# OCI ECGroup Node Configuration Script (UNIFIED - Device Agnostic)
# Works with both local NVMe drives and OCI block storage volumes
# Auto-detects available storage devices regardless of type

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
# Note: ECGroup images have CTDB pre-installed which depends on specific samba versions
# Use --nobest to skip packages with dependency conflicts, --nogpgcheck for SHA1 GPG key issues
echo "Updating system packages..."
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y update --nobest --nogpgcheck
    sudo $PKG_MGR -y install epel-release || true
    sudo $PKG_MGR -y install net-tools wget curl bind-utils nvme-cli lvm2 parted nfs-utils bc
else
    sudo apt-get -y update
    sudo apt-get -y install net-tools wget curl dnsutils nvme-cli lvm2 parted nfs-kernel-server bc
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
    # Install firewalld for Oracle/Rocky Linux
    echo "Installing firewalld..."
    sudo $PKG_MGR -y install firewalld

    # Configure firewalld for Oracle Linux
    echo "Configuring firewalld..."
    sudo systemctl enable firewalld || echo "Could not enable firewalld"
    sudo systemctl start firewalld || echo "Could not start firewalld"

    # Open required ports for ECGroup/RozoFS
    sudo firewall-cmd --permanent --add-port=22/tcp || true
    sudo firewall-cmd --permanent --add-port=873/tcp || true
    sudo firewall-cmd --permanent --add-port=9090/tcp || true
    sudo firewall-cmd --permanent --add-port=50000-51000/tcp || true
    # RozoFS specific ports (matching ansible configuration)
    sudo firewall-cmd --permanent --add-port=52000-52008/tcp || true
    sudo firewall-cmd --permanent --add-port=53000-53008/tcp || true
    sudo firewall-cmd --permanent --add-port=41001/tcp || true
    # NFS ports for Hammerspace integration
    sudo firewall-cmd --permanent --add-port=2049/tcp || true
    sudo firewall-cmd --permanent --add-port=20048/tcp || true
    sudo firewall-cmd --permanent --add-port=111/tcp || true
    sudo firewall-cmd --reload || true
else
    # Configure ufw for Ubuntu/Debian
    if command -v ufw &> /dev/null; then
        sudo ufw allow 22/tcp
        sudo ufw allow 873/tcp
        sudo ufw allow 9090/tcp
        sudo ufw allow 50000:51000/tcp
        # RozoFS specific ports
        sudo ufw allow 52000:52008/tcp
        sudo ufw allow 53000:53008/tcp
        sudo ufw allow 41001/tcp
        # NFS ports for Hammerspace integration
        sudo ufw allow 2049/tcp
        sudo ufw allow 20048/tcp
        sudo ufw allow 111/tcp
        sudo ufw --force enable
    else
        echo "ufw not available on this system, skipping firewall configuration"
    fi
fi

# Verify SELinux configuration
echo "Verifying SELinux configuration..."
if [ "$OS_TYPE" = "oracle" ] && command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce)
    echo "SELinux status: $SELINUX_STATUS"
    # Image should have SELinux already disabled
    # If SELinux is enabled, log a warning but continue
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo "WARNING: SELinux is in Enforcing mode. Expected Disabled mode in custom image."
        echo "Continuing with current SELinux configuration..."
    fi
else
    echo "SELinux not present or not applicable for this OS"
fi

# === UNIFIED STORAGE DEVICE DETECTION ===
echo "=== Detecting available storage devices (device-agnostic) ==="

# Create directory for RozoFS device information
sudo mkdir -p /etc/rozofs
sudo mkdir -p /var/log/rozofs

# Initialize device arrays
NVME_DEVICES=()
BLOCK_DEVICES=()
ALL_STORAGE_DEVICES=()

# Detect local NVMe drives (DenseIO shapes)
echo "Scanning for local NVMe drives..."
for dev in /dev/nvme[0-9]n[0-9]; do
    if [ -b "$dev" ]; then
        # Check if it's NOT the boot device
        if ! lsblk -no MOUNTPOINT "$dev" | grep -q "^/$\|^/boot"; then
            size=$(lsblk -bno SIZE "$dev" | head -1)
            size_tb=$(echo "scale=1; $size / 1099511627776" | bc)
            echo "  Found NVMe: $dev (${size_tb}T)"
            NVME_DEVICES+=("$dev")
            ALL_STORAGE_DEVICES+=("nvme:$dev:${size_tb}T")
        fi
    fi
done

# Detect OCI block storage volumes
echo "Scanning for OCI block storage volumes..."
for dev in /dev/sd[b-z] /dev/oracleoci/oraclevd[b-z]; do
    if [ -b "$dev" ] 2>/dev/null; then
        # Check if it's not mounted
        if ! lsblk -no MOUNTPOINT "$dev" | grep -q "."; then
            size=$(lsblk -bno SIZE "$dev" | head -1)
            size_gb=$(echo "scale=0; $size / 1073741824" | bc)
            echo "  Found block volume: $dev (${size_gb}G)"
            BLOCK_DEVICES+=("$dev")
            ALL_STORAGE_DEVICES+=("block:$dev:${size_gb}G")
        fi
    fi
done

# Save device information for RozoFS
echo "Saving detected devices to /etc/rozofs/available_devices.txt..."
{
    echo "# Available storage devices detected on $(date)"
    echo "# Format: TYPE:DEVICE:SIZE"
    for device_info in "${ALL_STORAGE_DEVICES[@]}"; do
        echo "$device_info"
    done
} | sudo tee /etc/rozofs/available_devices.txt > /dev/null

# Determine storage type
if [ ${#NVME_DEVICES[@]} -gt 0 ]; then
    STORAGE_TYPE="nvme"
    PRIMARY_DEVICES=("${NVME_DEVICES[@]}")
    echo "Storage type: Local NVMe (${#NVME_DEVICES[@]} drives detected)"
elif [ ${#BLOCK_DEVICES[@]} -gt 0 ]; then
    STORAGE_TYPE="block"
    PRIMARY_DEVICES=("${BLOCK_DEVICES[@]}")
    echo "Storage type: OCI Block Storage (${#BLOCK_DEVICES[@]} volumes detected)"
else
    echo "WARNING: No storage devices detected!"
    STORAGE_TYPE="none"
    PRIMARY_DEVICES=()
fi

# Save storage type for RozoFS scripts
echo "$STORAGE_TYPE" | sudo tee /etc/rozofs/storage_type.txt > /dev/null

echo "Total storage devices available for RozoFS: ${#ALL_STORAGE_DEVICES[@]}"

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

# Log completion
echo "=== OCI ECGroup node configuration completed successfully ==="
echo "Instance configured for OCI environment with ECGroup requirements"
echo "Target user: $TARGET_USER"
echo "Admin user created: admin"
echo "Storage type detected: $STORAGE_TYPE"
echo "Total storage devices: ${#ALL_STORAGE_DEVICES[@]}"

# Final system update and cleanup
# Use --nobest to skip packages with dependency conflicts, --nogpgcheck for SHA1 GPG key issues
if [ "$OS_TYPE" = "oracle" ]; then
    sudo $PKG_MGR -y upgrade --nobest --nogpgcheck || true
    sudo $PKG_MGR clean all
else
    sudo apt-get -y upgrade
    sudo apt-get autoremove -y
    sudo apt-get autoclean
fi

echo "OCI ECGroup node setup complete. System ready for RozoFS installation."
