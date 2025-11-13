#!/bin/bash

# OCI Client Configuration Script
# Updated for Oracle Cloud Infrastructure compatibility

# Update system and install required packages for OCI
# You can modify this based upon your needs

# Detect OS and configure accordingly
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    # Oracle Linux or RHEL-based systems
    PKG_MGR="dnf"
    if ! command -v dnf &> /dev/null; then
        PKG_MGR="yum"
    fi
    
    # Enable EPEL repository for additional packages
    sudo $PKG_MGR -y install epel-release || true
    
    # Update all packages
    sudo $PKG_MGR -y update
    
    # Install required packages for Oracle Linux
    sudo $PKG_MGR install -y python3-pip git bc nfs-utils screen net-tools fio wget curl
    
    # Install NFS client utilities
    sudo $PKG_MGR install -y nfs-utils rpcbind
    sudo systemctl enable rpcbind nfs-client.target
    sudo systemctl start rpcbind
    
else
    # Ubuntu/Debian systems
    sudo apt-get -y update
    sudo apt-get install -y python3-pip git bc nfs-common screen net-tools fio wget curl
    
    # Upgrade all the installed packages
    sudo apt-get -y upgrade
fi

# WARNING!!
# DO NOT MODIFY ANYTHING BELOW THIS LINE OR INSTANCES MAY NOT START CORRECTLY!
# ----------------------------------------------------------------------------

TARGET_USER="${TARGET_USER}"
TARGET_HOME="${TARGET_HOME}"
SSH_KEYS="${SSH_KEYS}"

# Set default user for OCI if not specified
if [ -z "$TARGET_USER" ]; then
    if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
        TARGET_USER="opc"  # Default for Oracle Linux
        TARGET_HOME="/home/opc"
    else
        TARGET_USER="ubuntu"  # Default for Ubuntu
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

# OCI-specific network optimizations
echo "Applying OCI network optimizations..."
sudo tee -a /etc/sysctl.conf > /dev/null <<'EOF'
# OCI Network optimizations for client workloads
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
EOF

# Apply sysctl changes
sudo sysctl -p

# Create NFS test mountpoint with proper permissions
echo "Creating NFS test mountpoint..."
sudo mkdir -p /mnt/nfs-test
sudo chmod 777 /mnt/nfs-test

# Create additional mountpoints for Hammerspace testing
sudo mkdir -p /mnt/hammerspace
sudo chmod 777 /mnt/hammerspace

# SSH Key Management for OCI
echo "Managing SSH keys..."
if [ -n "${SSH_KEYS}" ]; then
    mkdir -p "$TARGET_HOME/.ssh"
    chmod 700 "$TARGET_HOME/.ssh"
    touch "$TARGET_HOME/.ssh/authorized_keys"
    
    # Process keys one by one to avoid multi-line issues
    echo "${SSH_KEYS}" | while read -r key; do
        if [ -n "$key" ] && ! grep -qF "$key" "$TARGET_HOME/.ssh/authorized_keys"; then
            echo "$key" >> "$TARGET_HOME/.ssh/authorized_keys"
        fi
    done

    chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"
fi

# Configure OCI-specific performance tuning
echo "Configuring OCI performance tuning..."

# Set up I/O scheduler for OCI block volumes
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    # Oracle Linux specific tuning
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/scheduler}="mq-deadline"' | sudo tee /etc/udev/rules.d/60-oci-block-storage.rules
    echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"' | sudo tee -a /etc/udev/rules.d/60-oci-block-storage.rules
else
    # Ubuntu specific tuning
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/scheduler}="mq-deadline"' | sudo tee /etc/udev/rules.d/60-oci-block-storage.rules
    echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"' | sudo tee -a /etc/udev/rules.d/60-oci-block-storage.rules
fi

# Configure limits for high-performance workloads
sudo tee -a /etc/security/limits.conf > /dev/null <<'EOF'
# OCI Performance limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Install and configure performance monitoring tools
echo "Installing performance monitoring tools..."
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    sudo $PKG_MGR install -y htop iotop sysstat lsof tcpdump
    # Enable and start performance monitoring
    sudo systemctl enable sysstat
    sudo systemctl start sysstat
else
    sudo apt-get install -y htop iotop sysstat lsof tcpdump
fi

# Create performance testing scripts
echo "Creating performance testing scripts..."
sudo tee /usr/local/bin/oci-perf-test > /dev/null <<'EOF'
#!/bin/bash
# OCI Performance Testing Script

echo "=== OCI Client Performance Test ==="
echo "Date: $(date)"
echo "Instance: $(curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/displayName 2>/dev/null || echo 'Unknown')"
echo ""

echo "=== CPU Information ==="
lscpu | grep -E "(Model name|CPU\(s\)|Thread|Core)"
echo ""

echo "=== Memory Information ==="
free -h
echo ""

echo "=== Storage Information ==="
lsblk
echo ""

echo "=== Network Interface Information ==="
ip addr show | grep -E "(inet |UP,)"
echo ""

echo "=== Current Performance ==="
top -bn1 | head -20
EOF

sudo chmod +x /usr/local/bin/oci-perf-test

# Configure NFS client optimizations for OCI
echo "Configuring NFS client optimizations..."
sudo tee -a /etc/fstab > /dev/null <<'EOF'
# OCI NFS mount options template (commented out)
# nfs-server:/path /mnt/nfs-test nfs4 rsize=1048576,wsize=1048576,hard,intr,timeo=600 0 0
EOF

# Create client configuration summary
echo "Creating client configuration summary..."
sudo tee /home/$TARGET_USER/oci-client-info.txt > /dev/null <<EOF
=== OCI Client Configuration Summary ===
Date: $(date)
Target User: $TARGET_USER
Target Home: $TARGET_HOME
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
Kernel: $(uname -r)

=== Installed Packages ===
- NFS utilities for mounting Hammerspace shares
- Performance testing tools (fio, iotop, htop)
- Network utilities
- Development tools (git, python3-pip)

=== Mount Points Created ===
- /mnt/nfs-test (NFS testing)
- /mnt/hammerspace (Hammerspace shares)

=== Performance Scripts ===
- /usr/local/bin/oci-perf-test (System performance overview)

=== Next Steps ===
1. Mount Hammerspace shares: sudo mount -t nfs4 <hammerspace-ip>:/share /mnt/hammerspace
2. Run performance tests: oci-perf-test
3. Test I/O performance: fio --name=test --ioengine=libaio --size=1G --bs=4k --rw=randrw --numjobs=4

EOF

chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/oci-client-info.txt

# Final system updates and cleanup
echo "Performing final system update..."
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    sudo $PKG_MGR -y upgrade
    sudo $PKG_MGR clean all
else
    sudo apt-get -y upgrade
    sudo apt-get autoremove -y
    sudo apt-get autoclean
fi

echo "=== OCI Client Configuration Complete ==="
echo "Client configured for Oracle Cloud Infrastructure"
echo "Target user: $TARGET_USER"
echo "Configuration summary: /home/$TARGET_USER/oci-client-info.txt"
echo "Ready for Hammerspace client operations"

# Reboot to apply all changes
echo "Rebooting to apply all configuration changes..."
sudo reboot