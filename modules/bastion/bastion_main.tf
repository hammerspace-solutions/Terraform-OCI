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
# modules/bastion/bastion_main.tf
#
# This file contains the main logic for the bastion client module. It creates
# the compute instances and network security group.
# -----------------------------------------------------------------------------

# Data source to validate shape availability
data "oci_core_shapes" "bastion_shapes" {
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.shape]
  }
}

# Data source for image validation
data "oci_core_image" "bastion_image" {
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

  bastion_shape_is_available = length(data.oci_core_shapes.bastion_shapes.shapes) > 0

  resource_prefix = "${var.common_config.project_name}-bastion"

  freeform_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })

  # SSH metadata
  ssh_authorized_keys = join("\n", concat(
    compact([var.common_config.ssh_public_key]),
    local.ssh_public_keys
  ))
}

# Network Security Group for the bastion instances
resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix}-nsg"
  freeform_tags  = local.freeform_tags
}

# NSG Security Rules - Allow all ingress from allowed source CIDR blocks
resource "oci_core_network_security_group_security_rule" "bastion_ingress" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = var.allowed_source_cidr_blocks[0]
  source_type               = "CIDR_BLOCK"
  description               = "Allow all traffic from allowed sources"
}

# NSG Security Rules - Allow all egress
resource "oci_core_network_security_group_security_rule" "bastion_egress" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound traffic"
}

# Generate unique hostnames for each bastion instance
resource "random_id" "bastion_hostnames" {
  count       = var.instance_count
  byte_length = 2
}

# Launch OCI compute instances for bastion
resource "oci_core_instance" "bastion" {
  count               = var.instance_count
  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  shape               = var.shape

  # Flexible shape configuration
  dynamic "shape_config" {
    for_each = length(regexall("Flex$", var.shape)) > 0 ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_in_gbs
    }
  }

  create_vnic_details {
    subnet_id              = var.common_config.subnet_id
    display_name           = "${local.resource_prefix}-${count.index + 1}-vnic"
    assign_public_ip       = var.common_config.assign_public_ip
    hostname_label         = "bastion${count.index + 1}-${random_id.bastion_hostnames[count.index].hex}"
    nsg_ids                = [oci_core_network_security_group.bastion.id]
    skip_source_dest_check = false
    freeform_tags          = local.freeform_tags
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size
  }

  # Instance Options
  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }

  metadata = {
    ssh_authorized_keys = local.ssh_authorized_keys
    user_data          = var.user_data != "" ? base64encode(file(var.user_data)) : null
  }

  display_name = "${local.resource_prefix}-${count.index + 1}"
  freeform_tags = merge(local.freeform_tags, {
    Name = "${local.resource_prefix}-${count.index + 1}"
  })

  # Fault domain assignment
  fault_domain = var.common_config.fault_domain

  # Use capacity reservation if provided
  capacity_reservation_id = var.capacity_reservation_id

  lifecycle {
    ignore_changes = [source_details[0].source_id]
    
    precondition {
      condition     = local.bastion_shape_is_available
      error_message = "ERROR: Shape ${var.shape} for the Bastion is not available in AD ${var.common_config.availability_domain}."
    }
  }

  timeouts {
    create = "20m"
  }
}

