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
# modules/hammerspace/outputs.tf
#
# This file defines the outputs for the OCI Hammerspace module.
# -----------------------------------------------------------------------------

output "management_ip" {
  description = "Management IP address for the Hammerspace cluster."
  value       = [local.management_ip_for_url]
}

output "management_url" {
  description = "Management URL for the Hammerspace cluster."
  value       = [local.management_ip_for_url != "N/A - Anvil instance details not available." ? "https://${local.management_ip_for_url}:8443" : "N/A"]
}

output "anvil_instances" {
  description = "Details of deployed Anvil instances."
  sensitive   = true
  value = [
    for i, inst in oci_core_instance.anvil : {
      index      = i
      id         = inst.id
      private_ip = inst.private_ip
      public_ip  = inst.public_ip
      name       = inst.display_name
      shape      = inst.shape
      state      = inst.state
      type       = "standalone"
    }
  ]
}

output "dsx_instances" {
  description = "Details of deployed DSX instances."
  sensitive   = true
  value = [
    for i, inst in oci_core_instance.dsx : {
      index      = i + 1
      id         = inst.id
      private_ip = inst.private_ip
      public_ip  = inst.public_ip
      name       = inst.display_name
      shape      = inst.shape
      state      = inst.state
    }
  ]
}

output "anvil_private_ips" {
  description = "A list of the private IP addresses of the deployed Anvil instances."
  value       = [for inst in oci_core_instance.anvil : inst.private_ip]
}

output "anvil_public_ips" {
  description = "A list of the public IP addresses of the deployed Anvil instances (if assigned)."
  value       = [for inst in oci_core_instance.anvil : inst.public_ip]
}

output "dsx_private_ips" {
  description = "A list of the private IP addresses of the deployed DSX instances."
  value       = [for inst in oci_core_instance.dsx : inst.private_ip]
}

output "dsx_public_ips" {
  description = "A list of the public IP addresses of the deployed DSX instances (if assigned)."
  value       = [for inst in oci_core_instance.dsx : inst.public_ip]
}

output "primary_management_anvil_instance_id" {
  description = "Instance OCID of the primary Anvil node."
  value       = length(oci_core_instance.anvil) > 0 ? oci_core_instance.anvil[0].id : null
}

# Network Security Group outputs
output "anvil_network_security_group_id" {
  description = "OCID of the network security group created for Anvil instances"
  value       = length(oci_core_network_security_group.anvil_data_nsg) > 0 ? oci_core_network_security_group.anvil_data_nsg[0].id : null
}

output "dsx_network_security_group_id" {
  description = "OCID of the network security group created for DSX instances"
  value       = length(oci_core_network_security_group.dsx_nsg) > 0 ? oci_core_network_security_group.dsx_nsg[0].id : null
}

# Volume outputs
output "anvil_metadata_volume_ids" {
  description = "OCIDs of the metadata volumes attached to Anvil instances"
  value       = oci_core_volume.anvil_meta_vol[*].id
}

output "dsx_data_volume_ids" {
  description = "OCIDs of the data volumes attached to DSX instances"
  value       = oci_core_volume.dsx_data_vols[*].id
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the Hammerspace deployment"
  value = {
    anvil_count           = var.anvil_count
    anvil_deployment_type = var.anvil_count > 0 ? "standalone" : "none"
    dsx_count             = var.dsx_count
    total_instances       = var.anvil_count + var.dsx_count
    management_ip         = local.management_ip_for_url
    anvil_shape           = var.anvil_shape
    dsx_shape             = var.dsx_shape
    region                = var.common_config.region
    availability_domain   = var.common_config.availability_domain
  }
}

output "anvil_metadata_volume_details" {
  description = "Detailed information about Anvil metadata volumes"
  value = [
    for i, vol in oci_core_volume.anvil_meta_vol : {
      volume_id     = vol.id
      volume_name   = vol.display_name
      size_in_gbs   = vol.size_in_gbs
      instance_id   = oci_core_instance.anvil[i].id
      attachment_id = oci_core_volume_attachment.anvil_meta_vol_attach[i].id
      anvil_type    = "standalone"
    }
  ]
}

output "dsx_data_volume_details" {
  description = "Detailed information about DSX data volumes"
  value = [
    for i, vol in oci_core_volume.dsx_data_vols : {
      volume_id     = vol.id
      volume_name   = vol.display_name
      size_in_gbs   = vol.size_in_gbs
      instance_id   = oci_core_volume_attachment.dsx_data_vols_attach[i].instance_id
      attachment_id = oci_core_volume_attachment.dsx_data_vols_attach[i].id
      dsx_instance  = floor(i / var.dsx_block_volume_count) + 1
      volume_index  = (i % var.dsx_block_volume_count) + 1
    }
  ]
}
