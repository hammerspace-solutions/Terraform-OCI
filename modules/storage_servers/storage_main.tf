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
# modules/storage_servers/main.tf
#
# This file contains the main logic for the OCI Storage Servers module. It creates
# the compute instances, network security group, and attached block volumes.
# -----------------------------------------------------------------------------

# Data source to validate shape availability
data "oci_core_shapes" "storage_shapes" {
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.shape]
  }
}

# Data source for image validation
data "oci_core_image" "storage_image" {
  image_id = var.image_id
}

# Data source for subnet information
data "oci_core_subnet" "selected" {
  subnet_id = var.common_config.subnet_id
}

locals {
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
      trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  storage_shape_is_available = length(data.oci_core_shapes.storage_shapes.shapes) > 0

  processed_user_data = var.user_data != "" ? base64encode(templatefile(var.user_data, {
    SSH_KEYS           = var.common_config.ssh_public_key
    TARGET_USER        = var.target_user
    TARGET_HOME        = "/home/${var.target_user}"
    BLOCK_VOLUME_COUNT = var.block_volume_count
    RAID_LEVEL         = var.raid_level
    })) : base64encode(<<-EOF
#cloud-config
users:
  - name: ${var.target_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${var.common_config.ssh_public_key}

runcmd:
  - echo "RAID level: ${var.raid_level}"
  - echo "Block volume count: ${var.block_volume_count}"
EOF
  )

  resource_prefix = "${var.common_config.project_name}-storage"

  # Check if shape is Flex
  is_flex_shape = can(regex("Flex$", var.shape))

  # RAID level requirements mapping
  raid_requirements = {
    "raid-0" = 2
    "raid-5" = 3
    "raid-6" = 4
  }
}

# Network Security Group for storage instances
resource "oci_core_network_security_group" "storage" {
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix}-nsg"

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-nsg"
  }
}

# Security rules for storage NSG - Ingress (customize based on requirements)
resource "oci_core_network_security_group_security_rule" "storage_ingress_all" {
  network_security_group_id = oci_core_network_security_group.storage.id
  direction                 = "INGRESS"
  protocol                  = "all"

  source      = "0.0.0.0/0"
  source_type = "CIDR_BLOCK"

  description = "Allow all inbound traffic"
}

# Additional test-specific ingress rules (if enabled)
resource "oci_core_network_security_group_security_rule" "storage_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.storage.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP

  source      = "0.0.0.0/0"
  source_type = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }

  description = "Allow SSH access"
}

resource "oci_core_network_security_group_security_rule" "storage_ingress_icmp" {
  network_security_group_id = oci_core_network_security_group.storage.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP

  source      = "0.0.0.0/0"
  source_type = "CIDR_BLOCK"

  description = "Allow ICMP ping"
}

# Security rules for storage NSG - Egress
resource "oci_core_network_security_group_security_rule" "storage_egress" {
  network_security_group_id = oci_core_network_security_group.storage.id
  direction                 = "EGRESS"
  protocol                  = "all"

  destination      = "0.0.0.0/0"
  destination_type = "CIDR_BLOCK"

  description = "Allow all outbound traffic"
}

# Create storage compute instances
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
    nsg_ids          = [oci_core_network_security_group.storage.id]
    display_name     = "${local.resource_prefix}-${count.index + 1}-vnic"
  }

  # Metadata for cloud-init
  metadata = {
    ssh_authorized_keys = var.common_config.ssh_public_key
    user_data           = local.processed_user_data
  }

  # Fault domain (optional)
  fault_domain = var.common_config.fault_domain

  # Use capacity reservation if provided
  capacity_reservation_id = var.capacity_reservation_id

  lifecycle {
    precondition {
      condition     = var.block_volume_count >= local.raid_requirements[var.raid_level]
      error_message = "The selected RAID level (${var.raid_level}) requires at least ${local.raid_requirements[var.raid_level]} block volumes, but only ${var.block_volume_count} were specified."
    }

    precondition {
      condition     = local.storage_shape_is_available
      error_message = "ERROR: Instance shape ${var.shape} for Storage is not available in AD ${var.common_config.availability_domain}."
    }

    precondition {
      condition     = data.oci_core_image.storage_image.id == var.image_id
      error_message = "ERROR: Image ${var.image_id} not found or not accessible."
    }
  }

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-${count.index + 1}"
  }
}

# Create block volumes for RAID storage
resource "oci_core_volume" "storage_volumes" {
  count = var.instance_count * var.block_volume_count

  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix}-${floor(count.index / var.block_volume_count) + 1}-raid-vol-${(count.index % var.block_volume_count) + 1}"
  size_in_gbs         = var.block_volume_size

  # Performance configuration (if specified)
  vpus_per_gb = var.block_volume_iops != null ? ceil(var.block_volume_iops / var.block_volume_size) : null

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name        = "${local.resource_prefix}-${floor(count.index / var.block_volume_count) + 1}-raid-vol-${(count.index % var.block_volume_count) + 1}"
    Purpose     = "RAID-${var.raid_level}"
    InstanceNum = floor(count.index / var.block_volume_count) + 1
    VolumeNum   = (count.index % var.block_volume_count) + 1
  }
}

# Attach block volumes to instances for RAID configuration
resource "oci_core_volume_attachment" "storage_volume_attachments" {
  count           = var.instance_count * var.block_volume_count
  attachment_type = var.block_volume_type
  instance_id     = oci_core_instance.this[floor(count.index / var.block_volume_count)].id
  volume_id       = oci_core_volume.storage_volumes[count.index].id
  display_name    = "${local.resource_prefix}-${floor(count.index / var.block_volume_count) + 1}-raid-attachment-${(count.index % var.block_volume_count) + 1}"
}
