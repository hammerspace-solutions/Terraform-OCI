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
ECGROUP_USER="rocky"  # Default user for ECGroup instances (Rocky Linux)

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

echo "[configure-ecgroup] EC_MD_ARRAY = $eg_md_array"

# === DYNAMIC DEVICE DETECTION (Device-Agnostic Configuration) ===
# Query first node for actual storage type instead of hardcoding
# This makes the configuration work with both NVMe and block storage

first_node_ip=$(awk '/^\[ecgroup_nodes\]/{flag=1; next} /^\[/{flag=0} flag && /^[0-9]/{print $1; exit}' "$INVENTORY_FILE")

echo "[configure-ecgroup] Detecting storage type from first node: $first_node_ip"

# Query the node for its detected storage type
storage_type=$(ssh -i "$ECGROUP_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  "$ECGROUP_USER@$first_node_ip" "cat /etc/rozofs/storage_type.txt 2>/dev/null || echo 'unknown'")

echo "[configure-ecgroup] Detected storage type: $storage_type"

# Auto-detect device type by getting raw device size and calculating like RozoFS does
echo "[configure-ecgroup] Detecting device type from node..."

# Get the device path from available_devices.txt
device_path=$(ssh -i "$ECGROUP_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  "$ECGROUP_USER@$first_node_ip" \
  "grep -v '^#' /etc/rozofs/available_devices.txt 2>/dev/null | head -1 | cut -d: -f2 || echo ''")

echo "[configure-ecgroup] Device path: $device_path"

if [ -n "$device_path" ] && [ "$device_path" != "" ]; then
    # Get raw device size in bytes
    raw_size_bytes=$(ssh -i "$ECGROUP_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
      "$ECGROUP_USER@$first_node_ip" \
      "lsblk -b -d -o SIZE $device_path 2>/dev/null | tail -1 || echo '0'")

    echo "[configure-ecgroup] Raw size bytes: $raw_size_bytes"

    # Calculate size in TiB with proper rounding (RozoFS uses TiB = 2^40 bytes)
    if [ "$raw_size_bytes" != "0" ] && [ -n "$raw_size_bytes" ]; then
        device_size=$(echo "$raw_size_bytes" | awk '{printf "%.1f", $1/1099511627776}')
        echo "[configure-ecgroup] Calculated device size: ${device_size}T"

        if [ "$storage_type" = "nvme" ]; then
            eg_storage_array="NVME_${device_size}T"
        else
            eg_storage_array="HDD_${device_size}T"
        fi
    else
        echo "[configure-ecgroup] WARNING: Could not get device size, using inventory value"
        eg_storage_array=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /ecgroup_storage_array = / \
        {sub(/.*= /, ""); print}' "$INVENTORY_FILE")
    fi
else
    echo "[configure-ecgroup] WARNING: No device found, using inventory value"
    eg_storage_array=$(awk '/^\[all:vars\]$/{flag=1; next} /^\[.*\]$/{flag=0} flag && /ecgroup_storage_array = / \
    {sub(/.*= /, ""); print}' "$INVENTORY_FILE")
fi

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
  ROOT_USER="root"                   # root user needed for ssh

  # 6. Create temporary ECGroup inventory

  tmp_inventory=$(mktemp)
  echo "[ecgroup]" > "$tmp_inventory"
  for host in $ecgroup_hosts; do
    echo "$host ansible_user=$ECGROUP_USER ansible_ssh_private_key_file=$ECGROUP_PRIVATE_KEY_PATH" >> "$tmp_inventory"
  done

  echo "[configure-ecgroup] --- Inventory File: $tmp_inventory"
  cat "$tmp_inventory"

  # 7. Combined playbook for configuring ECGroup (OCI-optimized with Rocky fixes)

  tmp_playbook=$(mktemp)
  cat > "$tmp_playbook" <<EOF
- name: Configure ECGroup from the OCI controller node
  hosts: ecgroup
  gather_facts: true
  vars:
    ecgroup_name: "ecg"
    ecgroup_hosts: "$ecgroup_hosts"
    ecgroup_nodes: "$ecgroup_nodes"
    ecgroup_metadata_array: "$ECGROUP_METADATA_ARRAY"
    ecgroup_storage_array: "$ECGROUP_STORAGE_ARRAY"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  become: true
  tasks:
    - name: Wait for SSH to be available
      wait_for_connection:
        delay: 10
        timeout: 600

    - name: Create the cluster
      shell: >
        /opt/rozofs-installer/rozo_rozofs_create.sh -n {{ ecgroup_name }} -s "{{ ecgroup_hosts }}" -t external -d 1 -l 1
      register: create_cluster_result
      failed_when:
        - create_cluster_result.rc != 0
        - '"already declared" not in create_cluster_result.stdout'
      changed_when: create_cluster_result.rc == 0
      run_once: true

    - name: Add CTDB nodes
      shell: >
        /opt/rozofs-installer/rozo_rozofs_ctdb_node_add.sh -n {{ ecgroup_name }} -c "{{ ecgroup_hosts }}"
      register: ctdb_node_add_result
      failed_when:
        - ctdb_node_add_result.rc != 0
        - '"duplicated" not in ctdb_node_add_result.stdout'
      changed_when: ctdb_node_add_result.rc == 0
      run_once: true

    # DRBD Setup - Install kernel module and utilities from ELRepo
    - name: Configure ELRepo Archive repository for DRBD packages
      copy:
        dest: /etc/yum.repos.d/elrepo-archive.repo
        content: |
          [elrepo-archive]
          name=ELRepo.org Community Enterprise Linux Repository - Archive (el9)
          baseurl=https://mirror.rc.usf.edu/elrepo/archive/elrepo/el9/x86_64/
          enabled=1
          gpgcheck=1
          gpgkey=https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
          priority=10
          sslverify=no
        mode: '0644'

    - name: Import ELRepo GPG key
      rpm_key:
        key: https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        state: present

    - name: Clean yum cache
      command: yum clean all

    - name: Refresh yum metadata
      command: yum makecache

    - name: Remove old DRBD packages if present
      yum:
        name:
          - drbd-utils
          - drbd-selinux
          - kmod-drbd
        state: absent
      ignore_errors: true

    - name: Install DRBD9x packages from ELRepo
      yum:
        name:
          - kmod-drbd9x
          - drbd9x-utils
        state: present
        disable_gpg_check: true

    - name: Load DRBD kernel module
      modprobe:
        name: drbd
        state: present

    - name: Verify DRBD installation
      command: drbdadm --version
      register: drbd_version
      changed_when: false

    - name: Display DRBD version
      debug:
        msg: "DRBD installed successfully - {{ drbd_version.stdout_lines }}"

    - name: Setup DRBD with RozoFS metadata array
      shell: >
        /opt/rozofs-installer/rozo_drbd.sh -y -n {{ ecgroup_name }} -d "{{ ecgroup_metadata_array }}"
      register: drbd_setup_result
      failed_when:
        - drbd_setup_result.rc != 0
        - '"already" not in drbd_setup_result.stdout'
      changed_when: drbd_setup_result.rc == 0
      run_once: true

    - name: Create the array
      shell: >
        /opt/rozofs-installer/rozo_compute_cluster_balanced.sh -y -n {{ ecgroup_name }} -d "{{ ecgroup_storage_array }}"
      register: compute_cluster_result
      retries: 3
      delay: 10
      until: compute_cluster_result.rc == 0
      run_once: true

    - name: Propagate the configuration (may partially fail on export.conf copy)
      shell: >
        /opt/rozofs-installer/rozo_rozofs_install.sh -n {{ ecgroup_name }}
      register: install_result
      failed_when: false
      changed_when: install_result.rc == 0
      run_once: true

    - name: Check if export.conf was built
      stat:
        path: /opt/ROZOFS_CLUSTER/{{ ecgroup_name }}/EXPORT_CONF/export.conf
      register: export_conf_built
      run_once: true

    - name: Create export directories on all nodes
      file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
        owner: root
        group: root
      loop:
        - /srv/rozofs/exports/private
        - /srv/rozofs/exports/NVME

    - name: Read export.conf from first node
      slurp:
        src: /opt/ROZOFS_CLUSTER/{{ ecgroup_name }}/EXPORT_CONF/export.conf
      register: export_conf_content
      run_once: true
      when: export_conf_built.stat.exists

    - name: Distribute export.conf to all nodes
      copy:
        content: "{{ export_conf_content.content | b64decode }}"
        dest: /etc/rozofs/export.conf
        owner: root
        group: root
        mode: '0644'
        backup: yes
      when: export_conf_built.stat.exists

    - name: Restart exportd after config update
      systemd:
        name: rozofs-exportd
        state: restarted
        enabled: yes

    - name: Wait for exportd to start
      wait_for:
        timeout: 10

    # Rocky-specific fixes for NFS and RozoFS
    - name: Install firewalld (Rocky/RHEL)
      dnf:
        name: firewalld
        state: present
      when: ansible_os_family == "RedHat"

    - name: Enable and start firewalld (Rocky/RHEL)
      systemd:
        name: firewalld
        enabled: yes
        state: started
      when: ansible_os_family == "RedHat"

    - name: Open RozoFS ports in firewall (Rocky/RHEL)
      firewalld:
        port: "{{ item }}"
        permanent: yes
        state: enabled
        immediate: yes
      loop:
        - 52000-52008/tcp
        - 53000-53008/tcp
        - 41001/tcp
      when: ansible_os_family == "RedHat"

    - name: Open NFS ports in firewall (Rocky/RHEL)
      firewalld:
        port: "{{ item }}"
        permanent: yes
        state: enabled
        immediate: yes
      loop:
        - 111/tcp
        - 2049/tcp
        - 20048/tcp
      when: ansible_os_family == "RedHat"

    - name: Ensure rpcbind is enabled and started (Rocky/RHEL)
      systemd:
        name: rpcbind
        enabled: yes
        state: started
      when: ansible_os_family == "RedHat"

    - name: Verify SELinux status (should be Disabled in custom image)
      command: getenforce
      register: selinux_status
      failed_when: false
      changed_when: false
      when: ansible_os_family == "RedHat"

    - name: Log SELinux status
      debug:
        msg: "SELinux status: {{ selinux_status.stdout | default('N/A') }}"
      when:
        - ansible_os_family == "RedHat"
        - selinux_status.stdout is defined

    - name: Warn if SELinux is not disabled
      debug:
        msg: "WARNING: SELinux is {{ selinux_status.stdout }}. Expected Disabled mode in custom image."
      when:
        - ansible_os_family == "RedHat"
        - selinux_status.stdout is defined
        - selinux_status.stdout != "Disabled"

    # Configure NFS exports for Hammerspace integration
    - name: Set standalone mode to False for Hammerspace integration
      lineinfile:
        path: /etc/rozofs/rozofs.conf
        regexp: '^\s*standalone\s*='
        line: '   standalone                                         = False;'
        backup: yes

    - name: Update common_config.txt standalone setting
      lineinfile:
        path: /opt/ROZOFS_CLUSTER/{{ ecgroup_name }}/common_config.txt
        regexp: '^standalone '
        line: 'standalone False'
        backup: yes
      run_once: true

    - name: Restart exportd after standalone mode change
      systemd:
        name: rozofs-exportd
        state: restarted

    - name: Wait for exportd to fully start
      wait_for:
        timeout: 15

    # CRITICAL FIX: Clean up stale mount points to prevent rozofsmount SIGABRT
    # The rozofs_mountpoint_check() function aborts if stale entries exist in /proc/mounts
    - name: Kill any stale rozofsmount processes
      shell: sudo pkill -9 rozofsmount || true
      failed_when: false
      changed_when: false

    - name: Unmount any stale RozoFS mounts (lazy unmount)
      shell: sudo umount -l /mnt/rozofs/NVME || true
      failed_when: false
      changed_when: false

    - name: Remove and recreate clean mount point
      shell: |
        sudo rm -rf /mnt/rozofs/NVME
        sudo mkdir -p /mnt/rozofs/NVME
        sudo chmod 755 /mnt/rozofs/NVME
      changed_when: true

    # Use localhost-only mount for simplicity and reliability
    # Each node mounts its own local exportd instance
    - name: Mount RozoFS NVME export locally (localhost only)
      shell: |
        sudo rozofsmount -H localhost -E /srv/rozofs/exports/NVME /mnt/rozofs/NVME &
        sleep 10
        if df -h /mnt/rozofs/NVME 2>&1 | grep -q rozofs; then
          echo "Mount successful"
          exit 0
        else
          echo "Mount failed"
          exit 1
        fi
      args:
        executable: /bin/bash
      register: mount_result
      retries: 2
      delay: 3
      until: mount_result.rc == 0

    - name: Verify RozoFS mount is accessible
      command: df -h /mnt/rozofs/NVME
      register: df_output
      changed_when: false

    - name: Display mount information
      debug:
        msg: "RozoFS mounted: {{ df_output.stdout_lines }}"

    - name: Configure NFS export for Hammerspace
      copy:
        dest: /etc/exports
        content: |
          /mnt/rozofs/NVME    10.0.1.0/24(rw,sync,no_root_squash,no_subtree_check,fsid=1)
        backup: yes

    - name: Enable and start NFS server
      systemd:
        name: nfs-server
        enabled: yes
        state: started

    - name: Apply NFS exports
      command: exportfs -ra
      register: exportfs_result
      failed_when: false

    - name: Display exportfs result
      debug:
        var: exportfs_result

    - name: Verify NFS export (if exportfs succeeded)
      command: exportfs -v
      register: nfs_exports
      when: exportfs_result.rc == 0

    - name: Display NFS exports
      debug:
        var: nfs_exports.stdout_lines
      when:
        - exportfs_result.rc == 0
        - nfs_exports.stdout_lines is defined

    - name: Check RozoFS mount status
      command: mount | grep rozofs
      register: final_mount_check
      failed_when: false
      changed_when: false

    - name: Display mount status
      debug:
        var: final_mount_check.stdout_lines
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
