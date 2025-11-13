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
# modules/ecgroup/outputs.tf
#
# This file defines the outputs for the OCI ECGroup module.
# -----------------------------------------------------------------------------

output "nodes" {
  description = "Details about ECGroup nodes (OCID, Name, IPs)."
  value = [
    for i in oci_core_instance.nodes : {
      id         = i.id
      private_ip = i.private_ip
      public_ip  = i.public_ip
      name       = i.display_name
      shape      = i.shape
      state      = i.state
    }
  ]
}

output "node_ids" {
  description = "List of ECGroup node instance OCIDs"
  value       = oci_core_instance.nodes[*].id
}

output "private_ips" {
  description = "List of ECGroup node private IP addresses"
  value       = oci_core_instance.nodes[*].private_ip
}

output "public_ips" {
  description = "List of ECGroup node public IP addresses (if assigned)"
  value       = oci_core_instance.nodes[*].public_ip
}

output "node_names" {
  description = "List of ECGroup node names"
  value       = oci_core_instance.nodes[*].display_name
}

output "network_security_group_id" {
  description = "OCID of the network security group created for ECGroup nodes"
  value       = oci_core_network_security_group.ecgroup.id
}

output "metadata_volume_ids" {
  description = "List of metadata block volume OCIDs"
  value       = oci_core_volume.metadata_volumes[*].id
}

output "storage_volume_ids" {
  description = "List of storage block volume OCIDs"
  value       = oci_core_volume.storage_volumes[*].id
}

output "metadata_array" {
  description = "ECGroup metadata array description"
  value       = "OCI_BLOCK_${var.metadata_block_size}GB"
}

output "storage_array" {
  description = "ECGroup storage array description"
  value       = var.storage_block_count > 0 ? "OCI_BLOCK_${var.storage_block_size}GB" : "LOCAL_NVME_DENSEIO"
}

# Detailed volume information
output "metadata_volume_details" {
  description = "Detailed information about metadata volumes"
  value = [
    for i, vol in oci_core_volume.metadata_volumes : {
      volume_id       = vol.id
      volume_name     = vol.display_name
      size_in_gbs     = vol.size_in_gbs
      instance_id     = oci_core_volume_attachment.metadata_volume_attachments[i].instance_id
      attachment_id   = oci_core_volume_attachment.metadata_volume_attachments[i].id
      attachment_type = oci_core_volume_attachment.metadata_volume_attachments[i].attachment_type
      node_index      = i + 1
    }
  ]
}

output "storage_volume_details" {
  description = "Detailed information about storage volumes"
  value = [
    for i, vol in oci_core_volume.storage_volumes : {
      volume_id       = vol.id
      volume_name     = vol.display_name
      size_in_gbs     = vol.size_in_gbs
      instance_id     = oci_core_volume_attachment.storage_volume_attachments[i].instance_id
      attachment_id   = oci_core_volume_attachment.storage_volume_attachments[i].id
      attachment_type = oci_core_volume_attachment.storage_volume_attachments[i].attachment_type
      node_index      = floor(i / var.storage_block_count) + 1
      volume_index    = (i % var.storage_block_count) + 1
    }
  ]
}

# Node and volume mapping
output "node_volume_mapping" {
  description = "Mapping of ECGroup nodes to their attached volumes"
  value = {
    for idx, node in oci_core_instance.nodes : node.id => {
      node_name  = node.display_name
      private_ip = node.private_ip
      public_ip  = node.public_ip
      metadata_volume = {
        volume_id       = oci_core_volume.metadata_volumes[idx].id
        volume_name     = oci_core_volume.metadata_volumes[idx].display_name
        size_in_gbs     = oci_core_volume.metadata_volumes[idx].size_in_gbs
        attachment_id   = oci_core_volume_attachment.metadata_volume_attachments[idx].id
        attachment_type = oci_core_volume_attachment.metadata_volume_attachments[idx].attachment_type
      }
      storage_volumes = var.storage_block_count > 0 ? [
        for vol_idx in range(var.storage_block_count) : {
          volume_id       = oci_core_volume.storage_volumes[idx * var.storage_block_count + vol_idx].id
          volume_name     = oci_core_volume.storage_volumes[idx * var.storage_block_count + vol_idx].display_name
          size_in_gbs     = oci_core_volume.storage_volumes[idx * var.storage_block_count + vol_idx].size_in_gbs
          attachment_id   = oci_core_volume_attachment.storage_volume_attachments[idx * var.storage_block_count + vol_idx].id
          attachment_type = oci_core_volume_attachment.storage_volume_attachments[idx * var.storage_block_count + vol_idx].attachment_type
        }
      ] : []
      local_nvme_note = var.storage_block_count == 0 ? "Using local NVMe drives (DenseIO shape)" : null
    }
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the ECGroup deployment"
  value = {
    node_count               = var.node_count
    shape                    = var.shape
    is_denseio_shape         = can(regex("DenseIO", var.shape))
    local_nvme_note          = can(regex("DenseIO", var.shape)) ? "DenseIO shapes include local NVMe drives. BM.DenseIO.E5.128 has 8x 6.8TB NVMe drives." : "No local NVMe drives"
    metadata_volume_size_gb  = var.metadata_block_size
    storage_volume_size_gb   = var.storage_block_size
    storage_volumes_per_node = var.storage_block_count
    total_storage_volumes    = var.node_count * var.storage_block_count
    region                   = var.common_config.region
    availability_domain      = var.common_config.availability_domain
  }
}
