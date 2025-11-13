output "terraform_project_version" {
  description = "The version of the Terraform-OCI project configuration."
  value       = "2025.07.10-oci-refactor"
}

output "region" {
  description = "The OCI region where resources are deployed"
  value       = var.region
}

output "compartment_id" {
  description = "The OCID of the compartment where resources are deployed"
  value       = var.compartment_ocid
}

output "availability_domain" {
  description = "The availability domain where resources are deployed"
  value       = data.oci_identity_availability_domain.selected.name
}

output "networking_info" {
  description = "Networking configuration information"
  value = {
    vcn_id              = local.vcn_id
    subnet_id           = local.subnet_id
    nat_gateway_id      = local.effective_nat_gateway_id
    existing_nat_gateway_found = local.existing_nat_gateway_id != ""
    created_new_network = (var.vcn_id == "" || var.subnet_id == "") && var.create_networking
    message             = (var.vcn_id == "" || var.subnet_id == "") && var.create_networking ? "Created new VCN and subnet" : "Using existing VCN and subnet"
    nat_gateway_message = local.existing_nat_gateway_id != "" ? "Using existing NAT gateway found in VCN" : (
      local.effective_nat_gateway_id != "" ? "Using/creating NAT gateway" : "No NAT gateway configured"
    )
  }
}

output "nat_gateway_check" {
  description = "NAT gateway check for Hammerspace deployment"
  value = {
    hammerspace_anvil_count = var.hammerspace_anvil_count
    assign_public_ip = var.assign_public_ip
    nat_gateway_provided = local.effective_nat_gateway_id != "" ? true : false
    nat_gateway_id = local.effective_nat_gateway_id
    message = var.hammerspace_anvil_count == 2 && !var.assign_public_ip ? (
      local.effective_nat_gateway_id != "" ? "✓ NAT gateway configured for Hammerspace anvil instances" : "✗ NAT gateway required but not configured"
    ) : "NAT gateway not required for this configuration"
  }
}

# -----------------------------------------------------------------------------
# Client Instance Outputs
# -----------------------------------------------------------------------------
output "client_instances" {
  description = "Client instance details (non-sensitive)."
  value       = try(module.clients[0].instance_details, null)
}

# output "client_instance_ids" {
#   description = "List of client instance OCIDs"
#   value       = length(module.clients) > 0 && length(module.clients[0].instance_details) > 0 ? [for instance in module.clients[0].instance_details : instance.id] : null
# }

# output "client_private_ips" {
#   description = "List of client instance private IP addresses"
#   value       = length(module.clients) > 0 && length(module.clients[0].instance_details) > 0 ? [for instance in module.clients[0].instance_details : instance.private_ip] : null
# }

# output "client_public_ips" {
#   description = "List of client instance public IP addresses (if assigned)"
#   value       = length(module.clients) > 0 && length(module.clients[0].instance_details) > 0 ? [for instance in module.clients[0].instance_details : try(instance.public_ip, null)] : null
# }

# -----------------------------------------------------------------------------
# Storage Instance Outputs
# -----------------------------------------------------------------------------
output "storage_instances" {
  description = "Storage instance details (non-sensitive)."
  value       = try(module.storage_servers[0].instance_details, null)
}

# output "storage_instance_ids" {
#   description = "List of storage instance OCIDs"
#   value       = length(module.storage_servers) > 0 && length(module.storage_servers[0].instance_details) > 0 ? [for instance in module.storage_servers[0].instance_details : instance.id] : null
# }

# output "storage_private_ips" {
#   description = "List of storage instance private IP addresses"
#   value       = length(module.storage_servers) > 0 && length(module.storage_servers[0].instance_details) > 0 ? [for instance in module.storage_servers[0].instance_details : instance.private_ip] : null
# }

# output "storage_public_ips" {
#   description = "List of storage instance public IP addresses (if assigned)"
#   value       = length(module.storage_servers) > 0 && length(module.storage_servers[0].instance_details) > 0 ? [for instance in module.storage_servers[0].instance_details : try(instance.public_ip, null)] : null
# }

# -----------------------------------------------------------------------------
# Hammerspace Outputs
# -----------------------------------------------------------------------------
output "hammerspace_anvil" {
  description = "Hammerspace Anvil details"
  value       = try(module.hammerspace[0].anvil_instances, null)
  sensitive   = true
}

output "hammerspace_dsx" {
  description = "Hammerspace DSX details"
  value       = try(module.hammerspace[0].dsx_instances, null)
  sensitive   = true
}

output "hammerspace_mgmt_ip" {
  description = "Hammerspace Management IP"
  value       = try(module.hammerspace[0].management_ip, null)
}

output "hammerspace_mgmt_url" {
  description = "Hammerspace Management URL"
  value       = try(module.hammerspace[0].management_url, null)
}

output "hammerspace_anvil_private_ips" {
  description = "A list of private IP addresses for the Hammerspace Anvil instances"
  value       = try(module.hammerspace[0].anvil_private_ips, null)
}

output "hammerspace_dsx_private_ips" {
  description = "A list of private IP addresses for the Hammerspace DSX instances"
  value       = try(module.hammerspace[0].dsx_private_ips, null)
}

output "hammerspace_anvil_public_ips" {
  description = "A list of public IP addresses for the Hammerspace Anvil instances (if assigned)"
  value       = try(module.hammerspace[0].anvil_public_ips, null)
}

output "hammerspace_dsx_public_ips" {
  description = "A list of public IP addresses for the Hammerspace DSX instances (if assigned)"
  value       = try(module.hammerspace[0].dsx_public_ips, null)
}

# -----------------------------------------------------------------------------
# ECGroup Outputs
# -----------------------------------------------------------------------------
output "ecgroup_nodes" {
  description = "ECGroup node details"
  value       = try(module.ecgroup[0].nodes, null)
  sensitive   = true
}

output "ecgroup_node_ids" {
  description = "List of ECGroup node instance OCIDs"
  value       = try([for node in module.ecgroup[0].nodes : node.id], null)
}

output "ecgroup_private_ips" {
  description = "List of ECGroup node private IP addresses"
  value       = try([for node in module.ecgroup[0].nodes : node.private_ip], null)
}

output "ecgroup_public_ips" {
  description = "List of ECGroup node public IP addresses (if assigned)"
  value       = try([for node in module.ecgroup[0].nodes : try(node.public_ip, null)], null)
}

output "ecgroup_metadata_array" {
  description = "ECGroup metadata array"
  value       = try(module.ecgroup[0].metadata_array, null)
  sensitive   = true
}

output "ecgroup_storage_array" {
  description = "ECGroup storage array"
  value       = try( module.ecgroup[0].storage_array, null)
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Ansible Outputs
# -----------------------------------------------------------------------------
output "ansible_details" {
  description = "Ansible configuration details"
  value       = try(module.ansible[0].instance_details, null)
}

# output "ansible_instance_ids" {
#   description = "List of Ansible instance OCIDs"
#   value       = length(module.ansible) > 0 && length(module.ansible[0].instance_details) > 0 ? [for instance in module.ansible[0].instance_details : instance.id] : null
# }

# output "ansible_private_ips" {
#   description = "List of Ansible instance private IP addresses"
#   value       = length(module.ansible) > 0 && length(module.ansible[0].instance_details) > 0 ? [for instance in module.ansible[0].instance_details : instance.private_ip] : null
# }

# output "ansible_public_ips" {
#   description = "List of Ansible instance public IP addresses (if assigned)"
#   value       = length(module.ansible) > 0 && length(module.ansible[0].instance_details) > 0 ? [for instance in module.ansible[0].instance_details : try(instance.public_ip, null)] : null
# }

# -----------------------------------------------------------------------------
# Summary Outputs
# -----------------------------------------------------------------------------
output "deployment_summary" {
  description = "Summary of deployed components"
  value = {
    project_name        = var.project_name
    region              = var.region
    availability_domain = data.oci_identity_availability_domain.selected.name
    components_deployed = var.deploy_components
    total_instances = {
      clients = length(module.clients) > 0 ? var.clients_instance_count : 0
      storage = length(module.storage_servers) > 0 ? var.storage_instance_count : 0
      anvil   = length(module.hammerspace) > 0 ? var.hammerspace_anvil_count : 0
      dsx     = length(module.hammerspace) > 0 ? var.hammerspace_dsx_count : 0
      ecgroup = length(module.ecgroup) > 0 ? var.ecgroup_node_count : 0
      ansible = length(module.ansible) > 0 ? var.ansible_instance_count : 0
    }
  }
}

output "bastion_instances" {
  description = "Bastion client instance details (non-sensitive)."
  value       = module.bastion[*].instance_details
}
