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
# modules/ecgroup/main.tf
#
# This file contains the main logic for the OCI ECGroup module. It creates the
# compute instances, network security group, and attached block volumes.
# -----------------------------------------------------------------------------

# Data source to validate shape availability
data "oci_core_shapes" "ecgroup_shapes" {
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.shape]
  }
}

# Data source for image validation
data "oci_core_image" "ecgroup_image" {
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

  ecgroup_shape_is_available = length(data.oci_core_shapes.ecgroup_shapes.shapes) > 0

  processed_user_data = var.user_data != "" ? base64encode(file(var.user_data)) : base64encode(<<-EOF
  #cloud-config
  users:
    - name: opc
      sudo: ALL=(ALL) NOPASSWD:ALL
      ssh_authorized_keys:
        - ${var.common_config.ssh_public_key}
  EOF
  )

  resource_prefix = "${var.common_config.project_name}-ecgroup"

  # Check if shape is Flex
  is_flex_shape = can(regex("Flex$", var.shape))

  # Check if shape is DenseIO (has local NVMe drives)
  is_denseio_shape = can(regex("DenseIO", var.shape))

  # === UNIFIED DEVICE-AGNOSTIC CONFIGURATION ===
  # Auto-detect storage strategy based on shape
  use_local_nvme    = local.is_denseio_shape
  use_block_storage = !local.is_denseio_shape

  # Calculate NVMe drives available (DenseIO shapes: 1 drive per 8 OCPUs)
  nvme_drives_per_node = local.is_denseio_shape ? floor(var.ocpus / 8) : 0

  # Calculate block storage volumes needed (if not using NVMe)
  block_volumes_per_node = local.use_block_storage ? var.storage_block_count : 0

  # Total devices per node (NVMe OR block storage, not both)
  total_devices_per_node = local.use_local_nvme ? local.nvme_drives_per_node : local.block_volumes_per_node

  # Total cluster devices
  total_cluster_devices = local.total_devices_per_node * var.node_count

  # Auto-calculate optimal RozoFS layout based on total devices
  # Layout 0 (2+1): 3-5 devices
  # Layout 1 (4+2): 6-11 devices
  # Layout 2 (8+4): 12+ devices
  optimal_layout = (
    local.total_cluster_devices >= 12 ? 2 :
    local.total_cluster_devices >= 6  ? 1 :
    0
  )

  # Device type string for RozoFS (NVME_6.2T or HDD_200G)
  device_type = local.use_local_nvme ? "NVME_6.2T" : "HDD_${var.storage_block_size}G"

  # Storage technology tag
  storage_technology = local.use_local_nvme ? "local-nvme" : "block-storage"
}

# Network Security Group for ECGroup instances
resource "oci_core_network_security_group" "ecgroup" {
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix}-nsg"

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-nsg"
  }
}

# Security rules for ECGroup NSG - Ingress (allow all for now, customize as needed)
resource "oci_core_network_security_group_security_rule" "ecgroup_ingress" {
  network_security_group_id = oci_core_network_security_group.ecgroup.id
  direction                 = "INGRESS"
  protocol                  = "all"

  source      = "0.0.0.0/0"
  source_type = "CIDR_BLOCK"

  description = "Allow all inbound traffic"
}

# Security rules for ECGroup NSG - Egress
resource "oci_core_network_security_group_security_rule" "ecgroup_egress" {
  network_security_group_id = oci_core_network_security_group.ecgroup.id
  direction                 = "EGRESS"
  protocol                  = "all"

  destination      = "0.0.0.0/0"
  destination_type = "CIDR_BLOCK"

  description = "Allow all outbound traffic"
}

# Create ECGroup compute instances
resource "oci_core_instance" "nodes" {
  count               = var.node_count
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
    nsg_ids          = [oci_core_network_security_group.ecgroup.id]
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
      condition     = var.node_count >= 4
      error_message = "ECGroup requires at least 4 nodes, but only ${var.node_count} were specified."
    }

    precondition {
      condition     = var.storage_block_count <= 22
      error_message = "ECGroup nodes are limited to 22 storage volumes, but ${var.storage_block_count} were specified."
    }

    precondition {
      condition     = var.storage_block_count * var.node_count >= 8 || (local.is_denseio_shape && var.storage_block_count == 0)
      error_message = "ECGroup requires at least 8 storage volumes, but only ${var.storage_block_count * var.node_count} were specified. DenseIO shapes can use storage_block_count=0 to leverage local NVMe drives."
    }

    precondition {
      condition     = local.ecgroup_shape_is_available
      error_message = "ERROR: Instance shape ${var.shape} for ECGroup is not available in AD ${var.common_config.availability_domain}."
    }

    precondition {
      condition     = data.oci_core_image.ecgroup_image.id == var.image_id
      error_message = "ERROR: Image ${var.image_id} not found or not accessible."
    }
  }

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name = "${local.resource_prefix}-${count.index + 1}"
  }
}

# Create metadata block volumes for ECGroup nodes
resource "oci_core_volume" "metadata_volumes" {
  count = var.node_count

  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix}-${count.index + 1}-metadata-vol"
  size_in_gbs         = var.metadata_block_size

  # Performance configuration (if specified)
  vpus_per_gb = var.metadata_block_iops != null ? ceil(var.metadata_block_iops / var.metadata_block_size) : null

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name      = "${local.resource_prefix}-${count.index + 1}-metadata-vol"
    Purpose   = "ECGroup-Metadata"
    NodeIndex = count.index + 1
  }
}

# Attach metadata volumes to ECGroup instances
resource "oci_core_volume_attachment" "metadata_volume_attachments" {
  count           = var.node_count
  attachment_type = var.metadata_block_type
  instance_id     = oci_core_instance.nodes[count.index].id
  volume_id       = oci_core_volume.metadata_volumes[count.index].id
  display_name    = "${local.resource_prefix}-${count.index + 1}-metadata-attachment"
}

# Create storage block volumes for ECGroup nodes
resource "oci_core_volume" "storage_volumes" {
  count = var.node_count * var.storage_block_count

  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix}-${floor(count.index / var.storage_block_count) + 1}-storage-vol-${(count.index % var.storage_block_count) + 1}"
  size_in_gbs         = var.storage_block_size

  # Performance configuration (if specified)
  vpus_per_gb = var.storage_block_iops != null ? ceil(var.storage_block_iops / var.storage_block_size) : null

  defined_tags = var.common_config.tags
  freeform_tags = {
    Name        = "${local.resource_prefix}-${floor(count.index / var.storage_block_count) + 1}-storage-vol-${(count.index % var.storage_block_count) + 1}"
    Purpose     = "ECGroup-Storage"
    NodeIndex   = floor(count.index / var.storage_block_count) + 1
    VolumeIndex = (count.index % var.storage_block_count) + 1
  }
}

# Attach storage volumes to ECGroup instances
resource "oci_core_volume_attachment" "storage_volume_attachments" {
  count           = var.node_count * var.storage_block_count
  attachment_type = var.storage_block_type
  instance_id     = oci_core_instance.nodes[floor(count.index / var.storage_block_count)].id
  volume_id       = oci_core_volume.storage_volumes[count.index].id
  display_name    = "${local.resource_prefix}-${floor(count.index / var.storage_block_count) + 1}-storage-attachment-${(count.index % var.storage_block_count) + 1}"
}
