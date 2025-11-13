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
# modules/clients/outputs.tf
#
# This file defines the outputs for the OCI Clients module.
# -----------------------------------------------------------------------------

output "instance_details" {
  description = "A list of non-sensitive details for client instances (OCID, Name, IPs)."
  value = [
    for i in oci_core_instance.this : {
      id         = i.id
      private_ip = i.private_ip
      public_ip  = i.public_ip
      name       = i.display_name
      shape      = i.shape
      state      = i.state
    }
  ]
}

output "instance_ids" {
  description = "List of client instance OCIDs"
  value       = oci_core_instance.this[*].id
}

output "private_ips" {
  description = "List of client instance private IP addresses"
  value       = oci_core_instance.this[*].private_ip
}

output "public_ips" {
  description = "List of client instance public IP addresses (if assigned)"
  value       = oci_core_instance.this[*].public_ip
}

output "instance_names" {
  description = "List of client instance names"
  value       = oci_core_instance.this[*].display_name
}

output "network_security_group_id" {
  description = "OCID of the network security group created for clients"
  value       = oci_core_network_security_group.client.id
}

output "volume_ids" {
  description = "List of additional block volume OCIDs attached to client instances"
  value       = oci_core_volume.client_volumes[*].id
}

output "volume_attachment_ids" {
  description = "List of volume attachment OCIDs"
  value       = oci_core_volume_attachment.client_volume_attachments[*].id
}

# Detailed volume information
output "volume_details" {
  description = "Detailed information about attached volumes"
  value = [
    for i, vol in oci_core_volume.client_volumes : {
      volume_id     = vol.id
      volume_name   = vol.display_name
      size_in_gbs   = vol.size_in_gbs
      instance_id   = oci_core_volume_attachment.client_volume_attachments[i].instance_id
      attachment_id = oci_core_volume_attachment.client_volume_attachments[i].id
    }
  ]
}

# Instance and volume mapping
output "instance_volume_mapping" {
  description = "Mapping of instances to their attached volumes"
  value = {
    for idx, instance in oci_core_instance.this : instance.id => {
      instance_name = instance.display_name
      private_ip    = instance.private_ip
      public_ip     = instance.public_ip
      volumes = [
        for vol_idx in range(var.block_volume_count) : {
          volume_id     = oci_core_volume.client_volumes[idx * var.block_volume_count + vol_idx].id
          volume_name   = oci_core_volume.client_volumes[idx * var.block_volume_count + vol_idx].display_name
          attachment_id = oci_core_volume_attachment.client_volume_attachments[idx * var.block_volume_count + vol_idx].id
        }
      ]
    }
  }
}
