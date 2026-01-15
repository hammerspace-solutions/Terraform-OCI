#!/bin/bash

# OCI ECGroup Node Configuration Script with NVMe Support
# Optimized for BM.DenseIO.E5.128 with local NVMe drives

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
    sudo $PKG_MGR -y install net-tools wget curl bind-utils nvme-cli lvm2 bc
else
    sudo apt-get -y update
    sudo apt-get -y install net-tools wget curl dnsutils nvme-cli lvm2 bc
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

# Configure SELinux for RozoFS compatibility
echo "Configuring SELinux for RozoFS..."
if [ "$OS_TYPE" = "oracle" ] && command -v getenforce &> /dev/null; then
    # Check if SELinux is enabled
    if [ "$(getenforce)" != "Disabled" ]; then
        echo "Setting SELinux to permissive mode for RozoFS compatibility"
        # Set to permissive immediately (no reboot required)
        sudo setenforce 0 || true

        # Make it permanent across reboots
        sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
        sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/sysconfig/selinux 2>/dev/null || true

        echo "SELinux set to permissive mode (allows operations, logs denials)"
        echo "Current status: $(getenforce)"
    else
        echo "SELinux is disabled, no changes needed"
    fi
else
    echo "SELinux not present or OS is Debian-based, skipping"
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

# Configure kernel parameters for OCI and NVMe
sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'
# OCI Network optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.core.netdev_max_backlog = 5000

# NVMe optimizations for DenseIO
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
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

#############################################################################
# NVMe Drive Discovery and Preparation for ECGroup
#############################################################################

echo "=============================================="
echo "Discovering Local NVMe Drives (DenseIO)"
echo "=============================================="

# Create directory for NVMe information
sudo mkdir -p /etc/ecgroup
sudo mkdir -p /var/log/ecgroup

# Discover NVMe drives (excluding boot device)
NVME_DRIVES=$(sudo nvme list | grep -E 'nvme[0-9]+n[0-9]+' | awk '{print $1}' | grep -v "$(df / | tail -1 | awk '{print $1}' | sed 's/p[0-9]*$//')" || true)

if [ -z "$NVME_DRIVES" ]; then
    echo "WARNING: No local NVMe drives found!"
    echo "This is expected for non-DenseIO shapes."
    exit 0
fi

echo "Found local NVMe drives:"
echo "$NVME_DRIVES"

# Count NVMe drives
NVME_COUNT=$(echo "$NVME_DRIVES" | wc -l)
echo "Total NVMe drives detected: $NVME_COUNT"

# Create inventory file for ECGroup
sudo tee /etc/ecgroup/nvme_inventory.txt > /dev/null <<EOF
# NVMe Drive Inventory for ECGroup
# Generated: $(date)
# Node: $(hostname)
# Total NVMe Drives: $NVME_COUNT
EOF

echo "$NVME_DRIVES" | sudo tee -a /etc/ecgroup/nvme_inventory.txt > /dev/null

# Create formatted list for ECGroup consumption
echo "Creating formatted NVMe list for ECGroup..."
NVME_LIST_FILE="/etc/ecgroup/nvme_drives.list"
sudo rm -f $NVME_LIST_FILE
echo "$NVME_DRIVES" | while read -r drive; do
    if [ -n "$drive" ]; then
        # Get drive information
        DRIVE_SIZE=$(sudo nvme id-ns "$drive" 2>/dev/null | grep 'nsze' | awk '{print $3}' || echo "unknown")
        echo "$drive" | sudo tee -a $NVME_LIST_FILE > /dev/null
        echo "  - Device: $drive (Size: $DRIVE_SIZE blocks)"
    fi
done

# Create metadata volume mapping (use first NVMe or attached block volume)
echo "Configuring storage metadata mapping..."
METADATA_DEVICE=$(lsblk -nd -o NAME,TYPE | grep -E 'disk' | grep -v nvme | head -1 | awk '{print "/dev/"$1}' || echo "")
if [ -z "$METADATA_DEVICE" ]; then
    # If no block volumes, use first NVMe for metadata
    METADATA_DEVICE=$(echo "$NVME_DRIVES" | head -1)
    echo "Using NVMe drive for metadata: $METADATA_DEVICE"
else
    echo "Using block volume for metadata: $METADATA_DEVICE"
fi

echo "$METADATA_DEVICE" | sudo tee /etc/ecgroup/metadata_device.txt > /dev/null

# Create storage volume list (remaining NVMe drives)
echo "Creating storage volume list..."
STORAGE_LIST_FILE="/etc/ecgroup/storage_devices.list"
sudo rm -f $STORAGE_LIST_FILE

echo "$NVME_DRIVES" | while read -r drive; do
    if [ -n "$drive" ]; then
        echo "$drive" | sudo tee -a $STORAGE_LIST_FILE > /dev/null
    fi
done

# Get block volumes (if any)
BLOCK_VOLUMES=$(lsblk -nd -o NAME,TYPE | grep 'disk' | grep -v nvme | awk '{print "/dev/"$1}' || true)
if [ -n "$BLOCK_VOLUMES" ]; then
    echo "Found additional block volumes:"
    echo "$BLOCK_VOLUMES"
    echo "$BLOCK_VOLUMES" | while read -r vol; do
        if [ -n "$vol" ]; then
            echo "$vol" | sudo tee -a $STORAGE_LIST_FILE > /dev/null
        fi
    done
fi

# Create summary report
echo "Creating NVMe configuration summary..."
sudo tee /etc/ecgroup/nvme_summary.txt > /dev/null <<EOF
=================================================
NVMe Configuration Summary for ECGroup
=================================================
Date: $(date)
Hostname: $(hostname)
OS: $OS_TYPE

NVMe Drives Detected: $NVME_COUNT
Metadata Device: $METADATA_DEVICE
Storage Devices: $(cat $STORAGE_LIST_FILE 2>/dev/null | wc -l)

NVMe Drive Details:
-------------------
EOF

echo "$NVME_DRIVES" | while read -r drive; do
    if [ -n "$drive" ] && [ -b "$drive" ]; then
        echo "Device: $drive" | sudo tee -a /etc/ecgroup/nvme_summary.txt > /dev/null
        sudo nvme id-ctrl "$drive" 2>/dev/null | grep -E "^(mn|sn|fr)" | sudo tee -a /etc/ecgroup/nvme_summary.txt > /dev/null || true
        echo "---" | sudo tee -a /etc/ecgroup/nvme_summary.txt > /dev/null
    fi
done

# Set proper permissions
sudo chmod 644 /etc/ecgroup/*.txt /etc/ecgroup/*.list 2>/dev/null || true

echo "=============================================="
echo "NVMe Discovery Complete!"
echo "=============================================="
echo "Configuration files created in /etc/ecgroup/"
echo "- nvme_inventory.txt : Full NVMe inventory"
echo "- nvme_drives.list   : List of all NVMe drives"
echo "- metadata_device.txt: Metadata volume device"
echo "- storage_devices.list: Storage volume devices"
echo "- nvme_summary.txt   : Complete summary"
echo "=============================================="

# Display summary
cat /etc/ecgroup/nvme_summary.txt

# Log completion
echo "OCI ECGroup node configuration with NVMe support completed successfully"
echo "Instance configured for OCI environment with ECGroup requirements"
echo "Target user: $TARGET_USER"
echo "Admin user created: admin"
echo "NVMe drives ready for ECGroup: $NVME_COUNT"

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

echo "=============================================="
echo "OCI ECGroup node setup complete."
echo "System ready for ECGroup installation with local NVMe storage."
echo "=============================================="

# Check if a reboot is needed (kernel upgrade)
# Compare running kernel with latest installed kernel
if [ "$OS_TYPE" = "oracle" ]; then
    RUNNING_KERNEL=$(uname -r)
    LATEST_KERNEL=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)

    echo "Running kernel: $RUNNING_KERNEL"
    echo "Latest installed kernel: $LATEST_KERNEL"

    if [ "$RUNNING_KERNEL" != "$LATEST_KERNEL" ]; then
        echo "Kernel upgrade detected. Rebooting to load new kernel for DRBD compatibility..."
        echo "Reboot initiated at $(date)" | sudo tee /var/log/ecgroup-reboot.log
        sudo reboot
    else
        echo "Kernel is up to date. No reboot needed."
    fi
fi
