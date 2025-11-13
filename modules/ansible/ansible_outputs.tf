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
# modules/ansible/outputs.tf
#
# This file defines the outputs for the OCI Ansible module.
# -----------------------------------------------------------------------------

output "instance_details" {
  description = "A list of non-sensitive details for Ansible instances (OCID, Name, IPs)."
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
  description = "List of Ansible instance OCIDs"
  value       = oci_core_instance.this[*].id
}

output "private_ips" {
  description = "List of Ansible instance private IP addresses"
  value       = oci_core_instance.this[*].private_ip
}

output "public_ips" {
  description = "List of Ansible instance public IP addresses (if assigned)"
  value       = oci_core_instance.this[*].public_ip
}

output "instance_names" {
  description = "List of Ansible instance names"
  value       = oci_core_instance.this[*].display_name
}

output "network_security_group_id" {
  description = "OCID of the network security group created for Ansible instances"
  value       = oci_core_network_security_group.ansible.id
}

# Ansible-specific outputs
output "ansible_inventory_files" {
  description = "List of generated Ansible inventory files"
  value       = local_file.ansible_inventory[*].filename
}

output "ansible_config_files" {
  description = "List of generated Ansible configuration files"
  value       = local_file.ansible_config[*].filename
}

output "ansible_controller_info" {
  description = "Information for connecting to the Ansible controller"
  value = [
    for i, instance in oci_core_instance.this : {
      instance_id    = instance.id
      instance_name  = instance.display_name
      private_ip     = instance.private_ip
      public_ip      = instance.public_ip
      ssh_user       = var.target_user
      ssh_command    = var.common_config.assign_public_ip ? "ssh ${var.target_user}@${instance.public_ip}" : "ssh ${var.target_user}@${instance.private_ip}"
      inventory_file = length(local_file.ansible_inventory) > i ? local_file.ansible_inventory[i].filename : null
      config_file    = length(local_file.ansible_config) > i ? local_file.ansible_config[i].filename : null
    }
  ]
}

# Target configuration information
output "target_configuration" {
  description = "Summary of target nodes and configuration"
  value = {
    volume_group_name  = var.volume_group_name
    share_name         = var.share_name
    mgmt_ip            = length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : ""
    total_target_nodes = length(jsondecode(var.target_nodes_json))
    storage_instances  = length(var.storage_instances)
    anvil_instances    = length(var.anvil_instances)
    ecgroup_nodes      = length(var.ecgroup_nodes)
    has_admin_key      = var.admin_private_key_path != ""
  }
}

# Hammerspace configuration
output "hammerspace_config" {
  description = "Hammerspace-related configuration details"
  value = {
    management_ip     = length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : ""
    volume_group_name = var.volume_group_name
    share_name        = var.share_name
    anvil_instances   = var.anvil_instances
    storage_instances = var.storage_instances
  }
  sensitive = true
}

# ECGroup configuration
output "ecgroup_config" {
  description = "ECGroup-related configuration details"
  value = {
    instance_ids   = var.ecgroup_instances
    node_ips       = var.ecgroup_nodes
    metadata_array = var.ecgroup_metadata_array
    storage_array  = var.ecgroup_storage_array
  }
  sensitive = true
}
