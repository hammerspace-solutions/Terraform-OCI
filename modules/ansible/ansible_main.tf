# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# modules/ansible/main.tf
#
# This file contains the main logic for the OCI Ansible module. It creates the
# compute instances, network security group, and generates Ansible configuration.
# -----------------------------------------------------------------------------

# Data source to validate shape availability
data "oci_core_shapes" "ansible_shapes" {
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.shape]
  }
}

# Data source for image validation
data "oci_core_image" "ansible_image" {
  image_id = var.image_id
}

locals {
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
      trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  ansible_shape_is_available = length(data.oci_core_shapes.ansible_shapes.shapes) > 0

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    ADMIN_USER_PASSWORD    = var.admin_user_password,
    TARGET_USER            = var.target_user,
    TARGET_HOME            = "/home/${var.target_user}",
    ANSIBLE_HOME           = "/home/${var.target_user}",
    ADMIN_PRIVATE_KEY      = var.admin_private_key_path != "" ? file(var.admin_private_key_path) : "",
    SSH_KEYS               = join("\n", local.ssh_public_keys),
    TARGET_NODES_JSON      = var.target_nodes_json,
    MGMT_IP                = length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : "",
    ANVIL_ID               = length(var.anvil_instances) > 0 ? var.anvil_instances[0].id : "",
    STORAGE_INSTANCES      = jsonencode(var.storage_instances),
    VG_NAME                     = var.volume_group_name,
    SHARE_NAME                  = var.share_name,
    ECGROUP_ADD_TO_HAMMERSPACE  = var.ecgroup_add_to_hammerspace,
    ECGROUP_VG_NAME             = var.ecgroup_volume_group_name,
    ECGROUP_SHARE_NAME          = var.ecgroup_share_name,
    ECGROUP_INSTANCES           = join(" ", var.ecgroup_instances),
    ECGROUP_HOSTS               = length(var.ecgroup_nodes) > 0 ? var.ecgroup_nodes[0] : "",
    ECGROUP_NODES               = join(" ", var.ecgroup_nodes),
    ECGROUP_METADATA_ARRAY      = var.ecgroup_metadata_array,
    ECGROUP_STORAGE_ARRAY       = var.ecgroup_storage_array
    }) : base64encode(<<-EOF
    #cloud-config
    packages:
      - ansible
      - python3-pip
      - git
    
    users:
      - name: ${var.target_user}
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${var.common_config.ssh_public_key}
    
    runcmd:
      - pip3 install --upgrade ansible
      - mkdir -p /home/${var.target_user}/ansible
      - chown ${var.target_user}:${var.target_user} /home/${var.target_user}/ansible
    EOF
  )

  resource_prefix = "${var.common_config.project_name}-ansible"

  # Check if shape is Flex
  is_flex_shape = can(regex("Flex$", var.shape))

  # Parse target nodes from JSON
  target_nodes = jsondecode(var.target_nodes_json)

  # Generate Ansible inventory content
  ansible_inventory_content = <<-EOF
[all:vars]
ansible_user=${var.target_user}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[hammerspace_anvil]
%{for anvil in var.anvil_instances~}
${anvil.name} ansible_host=${anvil.private_ip} ansible_user=${var.target_user}
%{endfor~}

[hammerspace_storage]
%{for storage in var.storage_instances~}
${storage.name} ansible_host=${storage.private_ip} ansible_user=${var.target_user}
%{endfor~}

[client_nodes]
%{for node in local.target_nodes~}
${node.name} ansible_host=${node.private_ip} ansible_user=${var.target_user}
%{endfor~}

[ecgroup_nodes]
%{for i, ip in var.ecgroup_nodes~}
ecgroup-${i + 1} ansible_host=${ip} ansible_user=${var.target_user}
%{endfor~}

[hammerspace:children]
hammerspace_anvil
hammerspace_storage

[all_nodes:children]
hammerspace
client_nodes
ecgroup_nodes
EOF

  # Generate Ansible configuration
  ansible_config_content = <<-EOF
[defaults]
inventory = ./inventory.ini
host_key_checking = False
remote_user = ${var.target_user}
private_key_file = ${var.admin_private_key_path != "" ? var.admin_private_key_path : "~/.ssh/id_rsa"}
timeout = 30
gathering = smart
fact_caching = memory

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
pipelining = True
EOF
}

# Network Security Group for Ansible instances
resource "oci_core_network_security_group" "ansible" {
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix}-nsg"

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-nsg"
  }
}

# Security rules for Ansible NSG - Ingress
resource "oci_core_network_security_group_security_rule" "ansible_ingress" {
  network_security_group_id = oci_core_network_security_group.ansible.id
  direction                 = "INGRESS"
  protocol                  = "all"

  source      = "0.0.0.0/0"
  source_type = "CIDR_BLOCK"

  description = "Allow all inbound traffic"
}

# Security rules for Ansible NSG - Egress
resource "oci_core_network_security_group_security_rule" "ansible_egress" {
  network_security_group_id = oci_core_network_security_group.ansible.id
  direction                 = "EGRESS"
  protocol                  = "all"

  destination      = "0.0.0.0/0"
  destination_type = "CIDR_BLOCK"

  description = "Allow all outbound traffic"
}

# Create Ansible compute instances
resource "oci_core_instance" "this" {
  count               = var.instance_count
  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix}-${count.index + 1}"
  shape               = var.shape

  # Handle Flex shapes with dynamic configuration
  dynamic "shape_config" {
    for_each = local.is_flex_shape ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_in_gbs
    }
  }

  # Source details (image)
  source_details {
    source_type = "image"
    source_id   = var.image_id

    # Boot volume size
    boot_volume_size_in_gbs = var.boot_volume_size
  }

  # Network configuration
  create_vnic_details {
    subnet_id        = var.common_config.subnet_id
    assign_public_ip = var.common_config.assign_public_ip
    nsg_ids          = [oci_core_network_security_group.ansible.id]
    display_name     = "${local.resource_prefix}-${count.index + 1}-vnic"
  }

  # Metadata for cloud-init
  metadata = {
    ssh_authorized_keys = var.common_config.ssh_public_key
    user_data           = base64encode(local.processed_user_data)
  }

  # Fault domain (optional)
  fault_domain = var.common_config.fault_domain

  # Use capacity reservation if provided
  capacity_reservation_id = var.capacity_reservation_id

  lifecycle {
    precondition {
      condition     = local.ansible_shape_is_available
      error_message = "ERROR: Instance shape ${var.shape} for Ansible is not available in AD ${var.common_config.availability_domain}."
    }

    precondition {
      condition     = data.oci_core_image.ansible_image.id == var.image_id
      error_message = "ERROR: Image ${var.image_id} not found or not accessible."
    }
  }

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-${count.index + 1}"
    Type = "Ansible-Controller"
  }
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  count           = var.instance_count
  content         = local.ansible_inventory_content
  filename        = "${path.root}/ansible-inventory-${count.index + 1}.ini"
  file_permission = "0644"

  depends_on = [oci_core_instance.this]
}

# Generate Ansible configuration file
resource "local_file" "ansible_config" {
  count           = var.instance_count
  content         = local.ansible_config_content
  filename        = "${path.root}/ansible-config-${count.index + 1}.cfg"
  file_permission = "0644"

  depends_on = [oci_core_instance.this]
}

# Generate a basic Hammerspace playbook (optional)
resource "local_file" "hammerspace_playbook" {
  count    = var.instance_count > 0 && length(var.anvil_instances) > 0 ? 1 : 0
  filename = "${path.root}/hammerspace-setup.yml"
  content  = <<-EOF
---
- name: Configure Hammerspace Environment
  hosts: all_nodes
  become: yes
  gather_facts: yes
  
  vars:
    hammerspace_mgmt_ip: "${length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : ""}"
    volume_group_name: "${var.volume_group_name}"
    share_name: "${var.share_name}"
  
  tasks:
    - name: Update system packages
      package:
        name: "*"
        state: latest
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
    
    - name: Install required packages
      package:
        name:
          - nfs-utils
          - curl
          - wget
        state: present
      when: ansible_os_family == "RedHat"
    
    - name: Install required packages (Debian/Ubuntu)
      package:
        name:
          - nfs-common
          - curl
          - wget
        state: present
      when: ansible_os_family == "Debian"
    
    - name: Create mount point for Hammerspace
      file:
        path: /mnt/hammerspace
        state: directory
        mode: '0755'
      when: hammerspace_mgmt_ip != ""
    
    - name: Mount Hammerspace share
      mount:
        path: /mnt/hammerspace
        src: "{{ hammerspace_mgmt_ip }}:/{{ share_name | default('global') }}"
        fstype: nfs
        opts: "rw,sync,hard,intr"
        state: mounted
      when: hammerspace_mgmt_ip != "" and share_name != ""
      ignore_errors: yes

- name: Configure Storage Nodes
  hosts: hammerspace_storage
  become: yes
  tasks:
    - name: Configure storage-specific settings
      debug:
        msg: "Configuring storage node {{ inventory_hostname }}"

- name: Configure Client Nodes  
  hosts: client_nodes
  become: yes
  tasks:
    - name: Configure client-specific settings
      debug:
        msg: "Configuring client node {{ inventory_hostname }}"

- name: Configure ECGroup Nodes
  hosts: ecgroup_nodes
  become: yes
  tasks:
    - name: Configure ECGroup-specific settings
      debug:
        msg: "Configuring ECGroup node {{ inventory_hostname }}"
EOF

  file_permission = "0644"
}

# Upload local fixed ansible job scripts to replace GitHub versions
# This provisioner ensures that local fixes are applied automatically during deployment
resource "null_resource" "upload_fixed_scripts" {
  count = var.instance_count

  # Trigger on instance changes or script file changes
  triggers = {
    instance_id = oci_core_instance.this[count.index].id
    scripts_hash = join(",", [
      for script in ["20-add-storage-nodes.sh", "21-add-volume-groups.sh", "22-add-storage-volumes.sh",
                     "23-create-shares.sh", "24-add-ecgroup-volume-group.sh", "25-create-ecgroup-share.sh"]
      : filemd5("${path.module}/ansible_job_files/${script}")
    ])
  }

  # Wait for cloud-init to complete before uploading (ensures directories exist)
  provisioner "local-exec" {
    command = "sleep 120"  # Wait for cloud-init to finish
  }

  # Upload all fixed scripts
  provisioner "local-exec" {
    command = <<-EOT
      for script in 20-add-storage-nodes.sh 21-add-volume-groups.sh 22-add-storage-volumes.sh 23-create-shares.sh 24-add-ecgroup-volume-group.sh 25-create-ecgroup-share.sh; do
        scp -i ${var.common_config.ssh_keys_dir}/ansible_admin_key \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            ${path.module}/ansible_job_files/$script \
            ubuntu@${oci_core_instance.this[count.index].public_ip}:/tmp/$script

        ssh -i ${var.common_config.ssh_keys_dir}/ansible_admin_key \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            ubuntu@${oci_core_instance.this[count.index].public_ip} \
            "sudo mv /tmp/$script /usr/local/ansible/jobs/$script && sudo chmod +x /usr/local/ansible/jobs/$script"
      done
    EOT
  }

  depends_on = [oci_core_instance.this]
}
