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
# main.tf
#
# This is the root module for the Terraform-OCI project. It defines the
# providers, pre-flight validations, and calls the component modules.
# -----------------------------------------------------------------------------

# Setup the provider
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Data Sources for Networking and Availability Domain
# -----------------------------------------------------------------------------
data "oci_core_vcn" "validation" {
  count  = var.vcn_id != "" ? 1 : 0
  vcn_id = var.vcn_id
}

data "oci_core_subnet" "this" {
  count     = var.subnet_id != "" ? 1 : 0
  subnet_id = var.subnet_id
}

data "oci_identity_availability_domain" "selected" {
  compartment_id = var.compartment_ocid
  ad_number      = var.ad_number
}

# -----------------------------------------------------------------------------
# Pre-flight checks for instance shape availability
# -----------------------------------------------------------------------------
data "oci_core_shapes" "anvil_shapes" {
  count = (local.deploy_hammerspace && !var.hammerspace_use_existing_anvil && var.hammerspace_anvil_count > 0) ? 1 : 0
  
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name
  filter {
    name   = "name"
    values = [var.hammerspace_anvil_instance_shape]
  }
}

check "anvil_instance_shape_is_available" {
  assert {
    condition     = !(local.deploy_hammerspace && !var.hammerspace_use_existing_anvil && var.hammerspace_anvil_count > 0) || length(data.oci_core_shapes.anvil_shapes[0].shapes) > 0
    error_message = "The specified Anvil instance shape (${var.hammerspace_anvil_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

data "oci_core_shapes" "dsx_shapes" {
  count = (local.deploy_hammerspace && !var.hammerspace_use_existing_dsx && var.hammerspace_dsx_count > 0) ? 1 : 0
  
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name
  filter {
    name   = "name"
    values = [var.hammerspace_dsx_instance_shape]
  }
}

check "dsx_instance_shape_is_available" {
  assert {
    condition     = !(local.deploy_hammerspace && !var.hammerspace_use_existing_dsx && var.hammerspace_dsx_count > 0) || length(data.oci_core_shapes.dsx_shapes[0].shapes) > 0
    error_message = "The specified DSX instance shape (${var.hammerspace_dsx_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

# Hammerspace image data source
data "oci_core_image" "hammerspace_image_check" {
  count    = (local.deploy_hammerspace && (!var.hammerspace_use_existing_anvil || !var.hammerspace_use_existing_dsx) && var.hammerspace_image_id != "") ? 1 : 0
  image_id = var.hammerspace_image_id
}

check "hammerspace_image_exists" {
  assert {
    condition     = !(local.deploy_hammerspace && (!var.hammerspace_use_existing_anvil || !var.hammerspace_use_existing_dsx) && var.hammerspace_image_id != "") || length(data.oci_core_image.hammerspace_image_check) == 0 || data.oci_core_image.hammerspace_image_check[0].id == var.hammerspace_image_id
    error_message = "Validation Error: The specified hammerspace_image_id (ID: ${var.hammerspace_image_id}) was not found in the region ${var.region}."
  }
}

# -----------------------------------------------------------------------------
# Pre-flight Validation for Networking
# -----------------------------------------------------------------------------
check "vcn_and_subnet_validation" {
  assert {
    condition = var.vcn_id == "" || var.subnet_id == "" || (
    length(data.oci_core_subnet.this) > 0 && 
    length(data.oci_core_vcn.validation) > 0 && 
    try(data.oci_core_subnet.this[0].vcn_id, "") == try(data.oci_core_vcn.validation[0].id, "")
  )
    error_message = "Validation Error: The provided subnet (ID: ${var.subnet_id}) does not belong to the provided VCN (ID: ${var.vcn_id})."
  }
}


data "oci_core_shapes" "client_shapes" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name

  filter {
    name   = "name"
    values = [var.clients_instance_shape]
  }
}

check "client_instance_shape_is_available" {
  assert {
    condition     = length(data.oci_core_shapes.client_shapes.shapes) > 0
    error_message = "The specified Client instance shape (${var.clients_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

data "oci_core_shapes" "storage_shapes" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name

  filter {
    name   = "name"
    values = [var.storage_instance_shape]
  }
}

check "storage_instance_shape_is_available" {
  assert {
    condition     = length(data.oci_core_shapes.storage_shapes.shapes) > 0
    error_message = "The specified Storage instance shape (${var.storage_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

data "oci_core_shapes" "ecgroup_shapes" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name

  filter {
    name   = "name"
    values = [var.ecgroup_instance_shape]
  }
}

check "ecgroup_node_instance_shape_is_available" {
  assert {
    condition     = length(data.oci_core_shapes.ecgroup_shapes.shapes) > 0
    error_message = "The specified ECGroup Node instance shape (${var.ecgroup_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

data "oci_core_shapes" "ansible_shapes" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name

  filter {
    name   = "name"
    values = [var.ansible_instance_shape]
  }
}

check "ansible_instance_shape_is_available" {
  assert {
    condition     = length(data.oci_core_shapes.ansible_shapes.shapes) > 0
    error_message = "The specified Ansible instance shape (${var.ansible_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

data "oci_core_shapes" "bastion_shapes" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.selected.name

  filter {
    name   = "name"
    values = [var.bastion_instance_shape]
  }
}

check "bastion_instance_shape_is_available" {
  assert {
    condition     = length(data.oci_core_shapes.bastion_shapes.shapes) > 0
    error_message = "The specified Bastion instance shape (${var.bastion_instance_shape}) is not available in the selected Availability Domain (${data.oci_identity_availability_domain.selected.name})."
  }
}

# -----------------------------------------------------------------------------
# Pre-flight checks for Image existence
# -----------------------------------------------------------------------------
check "client_image_exists" {
  data "oci_core_image" "client_image_check" {
    image_id = var.clients_image_id
  }

  assert {
    condition     = data.oci_core_image.client_image_check.id == var.clients_image_id
    error_message = "Validation Error: The specified clients_image_id (ID: ${var.clients_image_id}) was not found in the region ${var.region}."
  }
}

check "storage_image_exists" {
  data "oci_core_image" "storage_image_check" {
    image_id = var.storage_image_id
  }

  assert {
    condition     = data.oci_core_image.storage_image_check.id == var.storage_image_id
    error_message = "Validation Error: The specified storage_image_id (ID: ${var.storage_image_id}) was not found in the region ${var.region}."
  }
}


check "ansible_image_exists" {
  data "oci_core_image" "ansible_image_check" {
    image_id = var.ansible_image_id
  }

  assert {
    condition     = data.oci_core_image.ansible_image_check.id == var.ansible_image_id
    error_message = "Validation Error: The specified ansible_image_id (ID: ${var.ansible_image_id}) was not found in the region ${var.region}."
  }
}

check "bastion_image_exists" {
  data "oci_core_image" "bastion_image_check" {
    image_id = var.bastion_image_id
  }

  assert {
    condition     = data.oci_core_image.bastion_image_check.id == var.bastion_image_id
    error_message = "Validation Error: The specified bastion_image_id (ID: ${var.bastion_image_id}) was not found in the region ${var.region}."
  }
}

check "network_configuration" {
  assert {
    condition = (var.vcn_id != "" && var.subnet_id != "") || var.create_networking
    error_message = "Either provide both vcn_id and subnet_id for existing network resources, or enable create_networking to create new ones"
  }
}

check "nat_gateway_configuration" {
  assert {
    condition = !(
      var.hammerspace_anvil_count == 2 && 
      !var.assign_public_ip && 
      var.nat_gateway_id == "" && 
      (var.vcn_id != "" || var.subnet_id != "") &&
      !var.create_nat_gateway_for_existing_vcn
    )
    error_message = "When using existing VCN/subnet with hammerspace_anvil_count=2 and assign_public_ip=false, you must either provide nat_gateway_id or set create_nat_gateway_for_existing_vcn=true"
  }
}

# -----------------------------------------------------------------------------
# Networking Module - Create VCN/Subnet if not provided
# -----------------------------------------------------------------------------
module "networking" {
  count  = (var.vcn_id == "" || var.subnet_id == "") && var.create_networking ? 1 : 0
  source = "./modules/networking"

  compartment_id          = var.compartment_ocid
  region                  = var.region
  project_name            = var.project_name
  tags                    = var.tags
  vcn_cidr                = var.vcn_cidr
  subnet_cidr             = var.subnet_cidr
  availability_domain     = data.oci_identity_availability_domain.selected.name
  create_nat_gateway      = !var.assign_public_ip
  create_internet_gateway = var.assign_public_ip
}

# -----------------------------------------------------------------------------
# Find or Create NAT Gateway for Existing VCN
# -----------------------------------------------------------------------------
# First, try to find existing NAT gateway in the VCN
data "oci_core_nat_gateways" "existing" {
  count          = var.vcn_id != "" && var.nat_gateway_id == "" ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_id
  
  filter {
    name   = "state"
    values = ["AVAILABLE"]
  }
}

# Only create new NAT gateway if none exists
resource "oci_core_nat_gateway" "existing_vcn" {
  count = var.create_nat_gateway_for_existing_vcn && var.vcn_id != "" && var.nat_gateway_id == "" && !var.assign_public_ip && length(try(data.oci_core_nat_gateways.existing[0].nat_gateways, [])) == 0 ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_id
  display_name   = "${var.project_name}-nat-gateway"
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = "${var.project_name}-nat-gateway"
    Type = "NAT-Gateway"
  }
}




# -----------------------------------------------------------------------------
# Local Configuration and Component Deployment Flags
# -----------------------------------------------------------------------------
locals {
  # Use existing or newly created network resources
  vcn_id    = var.vcn_id != "" ? var.vcn_id : (var.create_networking ? module.networking[0].vcn_id : "")
  subnet_id = var.subnet_id != "" ? var.subnet_id : (var.create_networking ? module.networking[0].subnet_id : "")
  
  # Use existing NAT gateway or newly created one
  existing_nat_gateway_id = var.vcn_id != "" && var.nat_gateway_id == "" && length(data.oci_core_nat_gateways.existing) > 0 ? (
    length(try(data.oci_core_nat_gateways.existing[0].nat_gateways, [])) > 0 ? data.oci_core_nat_gateways.existing[0].nat_gateways[0].id : ""
  ) : ""
  
  effective_nat_gateway_id = var.nat_gateway_id != "" ? var.nat_gateway_id : (
    local.existing_nat_gateway_id != "" ? local.existing_nat_gateway_id : (
      (var.vcn_id == "" || var.subnet_id == "") && var.create_networking && !var.assign_public_ip ? 
      module.networking[0].nat_gateway_id : (
        var.create_nat_gateway_for_existing_vcn && var.vcn_id != "" && !var.assign_public_ip && length(try(data.oci_core_nat_gateways.existing[0].nat_gateways, [])) == 0 ?
        oci_core_nat_gateway.existing_vcn[0].id : ""
      )
    )
  )
  
  common_config = {
    region              = var.region
    availability_domain = data.oci_identity_availability_domain.selected.name
    compartment_id      = var.compartment_ocid
    vcn_id              = local.vcn_id
    subnet_id           = local.subnet_id
    ssh_public_key      = var.ssh_public_key
    tags                = var.tags
    project_name        = var.project_name
    assign_public_ip    = var.assign_public_ip
    ssh_keys_dir        = var.ssh_keys_dir
    fault_domain        = var.fault_domain != "" ? var.fault_domain : null
  }

  deploy_clients     = contains(var.deploy_components, "all") || contains(var.deploy_components, "clients")
  deploy_storage     = contains(var.deploy_components, "all") || contains(var.deploy_components, "storage")
  deploy_hammerspace = contains(var.deploy_components, "all") || contains(var.deploy_components, "hammerspace")
  deploy_ansible     = contains(var.deploy_components, "all") || contains(var.deploy_components, "ansible")
  deploy_ecgroup     = contains(var.deploy_components, "all") || contains(var.deploy_components, "ecgroup")
  deploy_bastion     = contains(var.deploy_components, "all") || contains(var.deploy_components, "bastion")

  all_ssh_nodes = concat(
    local.deploy_clients ? module.clients[0].instance_details : [],
    local.deploy_storage ? module.storage_servers[0].instance_details : []
  )

  # ECGroup image mapping for different OCI regions
  ecgroup_image_mapping = {
    "uk-london-1"    = "ocid1.image.oc1.uk-london-1.aaaa..." # Replace with actual OCIDs
    "us-ashburn-1"   = "ocid1.image.oc1.iad.aaaa..."
    "us-phoenix-1"   = "ocid1.image.oc1.phx.aaaa..."
    "eu-frankfurt-1" = "ocid1.image.oc1.eu-frankfurt-1.aaaa..."
  }

  select_ecgroup_image_for_region = lookup(local.ecgroup_image_mapping, var.region, var.ecgroup_image_id)
}

# -----------------------------------------------------------------------------
# Module Definitions (Without Capacity Reservations)
# -----------------------------------------------------------------------------

# Clients
module "clients" {
  count  = local.deploy_clients ? 1 : 0
  source = "./modules/clients"

  common_config           = local.common_config
  capacity_reservation_id = null # Disabled capacity reservations

  instance_count          = var.clients_instance_count
  image_id                = var.clients_image_id
  shape                   = var.clients_instance_shape
  ocpus                   = var.clients_ocpus
  memory_in_gbs           = var.clients_memory_gbs
  boot_volume_size        = var.clients_boot_volume_size
  boot_volume_type        = var.clients_boot_volume_type
  block_volume_count      = var.clients_block_volume_count
  block_volume_size       = var.clients_block_volume_size
  block_volume_type       = var.clients_block_volume_type
  block_volume_throughput = var.clients_block_volume_throughput
  block_volume_iops       = var.clients_block_volume_iops
  user_data               = var.clients_user_data
  target_user             = var.clients_target_user

  depends_on = [module.hammerspace]
}

# Storage Servers
module "storage_servers" {
  count  = local.deploy_storage ? 1 : 0
  source = "./modules/storage_servers"

  common_config           = local.common_config
  capacity_reservation_id = null # Disabled capacity reservations

  instance_count          = var.storage_instance_count
  image_id                = var.storage_image_id
  shape                   = var.storage_instance_shape
  ocpus                   = var.storage_ocpus
  memory_in_gbs           = var.storage_memory_gbs
  boot_volume_size        = var.storage_boot_volume_size
  boot_volume_type        = var.storage_boot_volume_type
  block_volume_count      = var.storage_block_volume_count
  raid_level              = var.storage_raid_level
  block_volume_size       = var.storage_block_volume_size
  block_volume_type       = var.storage_block_volume_type
  block_volume_throughput = var.storage_block_volume_throughput
  block_volume_iops       = var.storage_block_volume_iops
  user_data               = var.storage_user_data
  target_user             = var.storage_target_user

  depends_on = [module.hammerspace]
}

# Hammerspace
module "hammerspace" {

  deployment_name = var.deployment_name
  count  = local.deploy_hammerspace ? 1 : 0
  source = "./modules/hammerspace"

  common_config                 = local.common_config
  anvil_capacity_reservation_id = null # Disabled capacity reservations
  dsx_capacity_reservation_id   = null # Disabled capacity reservations

  image_id                = var.hammerspace_image_id
  profile_id              = var.hammerspace_profile_id
  anvil_security_group_id = var.hammerspace_anvil_security_group_id
  dsx_security_group_id   = var.hammerspace_dsx_security_group_id

  anvil_count                = var.hammerspace_anvil_count
  sa_anvil_destruction       = var.hammerspace_sa_anvil_destruction
  anvil_shape                = var.hammerspace_anvil_instance_shape
  anvil_ocpus                = var.hammerspace_anvil_ocpus
  anvil_memory_in_gbs        = var.hammerspace_anvil_memory_gbs
  anvil_meta_disk_size       = var.hammerspace_anvil_meta_disk_size
  anvil_meta_disk_type       = var.hammerspace_anvil_meta_disk_type
  anvil_meta_disk_iops       = var.hammerspace_anvil_meta_disk_iops
  anvil_meta_disk_throughput = var.hammerspace_anvil_meta_disk_throughput

  dsx_count                   = var.hammerspace_dsx_count
  dsx_shape                   = var.hammerspace_dsx_instance_shape
  dsx_ocpus                   = var.hammerspace_dsx_ocpus
  dsx_memory_in_gbs           = var.hammerspace_dsx_memory_gbs
  dsx_block_volume_size       = var.hammerspace_dsx_block_volume_size
  dsx_block_volume_type       = var.hammerspace_dsx_block_volume_type
  dsx_block_volume_iops       = var.hammerspace_dsx_block_volume_iops
  dsx_block_volume_throughput = var.hammerspace_dsx_block_volume_throughput
  dsx_block_volume_count      = var.hammerspace_dsx_block_volume_count
  dsx_add_vols                = var.hammerspace_dsx_add_vols
  
  # Network interface names (auto-detected based on shape if not specified)
  anvil_network_interface_name = ""
  dsx_network_interface_name   = ""

  api_key             = var.api_key
  config_file         = var.config_file
  admin_user_password = var.admin_user_password
  nat_gateway_id      = local.effective_nat_gateway_id
  
  # Existing infrastructure variables
  use_existing_anvil          = var.hammerspace_use_existing_anvil
  existing_anvil_ips          = var.hammerspace_existing_anvil_ips
  existing_anvil_password     = var.hammerspace_existing_anvil_password
  use_existing_dsx            = var.hammerspace_use_existing_dsx
  existing_dsx_ips            = var.hammerspace_existing_dsx_ips
}

module "ecgroup" {
  count  = local.deploy_ecgroup ? 1 : 0
  source = "./modules/ecgroup"

  common_config           = local.common_config
  capacity_reservation_id = null # Disabled capacity reservations

  node_count                = var.ecgroup_node_count
  image_id                  = local.select_ecgroup_image_for_region != "" ? local.select_ecgroup_image_for_region : var.ecgroup_image_id
  shape                     = var.ecgroup_instance_shape
  ocpus                     = var.ecgroup_ocpus
  memory_in_gbs             = var.ecgroup_memory_gbs
  boot_volume_size          = var.ecgroup_boot_volume_size
  boot_volume_type          = var.ecgroup_boot_volume_type
  metadata_block_type       = var.ecgroup_metadata_volume_type
  metadata_block_size       = var.ecgroup_metadata_volume_size
  metadata_block_throughput = var.ecgroup_metadata_volume_throughput
  metadata_block_iops       = var.ecgroup_metadata_volume_iops
  storage_block_count       = var.ecgroup_storage_volume_count
  storage_block_type        = var.ecgroup_storage_volume_type
  storage_block_size        = var.ecgroup_storage_volume_size
  storage_block_throughput  = var.ecgroup_storage_volume_throughput
  storage_block_iops        = var.ecgroup_storage_volume_iops
  user_data                 = var.ecgroup_user_data
}

module "bastion" {
  count  = local.deploy_bastion ? 1 : 0
  source = "./modules/bastion"

  common_config              = local.common_config
  capacity_reservation_id    = null # Disabled capacity reservations for now
  allowed_source_cidr_blocks = var.bastion_allowed_source_cidr_blocks

  instance_count   = var.bastion_instance_count
  image_id         = var.bastion_image_id
  shape            = var.bastion_instance_shape
  ocpus            = var.bastion_ocpus
  memory_in_gbs    = var.bastion_memory_gbs
  boot_volume_size = var.bastion_boot_volume_size
  boot_volume_type = var.bastion_boot_volume_type
  user_data        = var.bastion_user_data
  target_user      = var.bastion_target_user

  depends_on = [module.hammerspace]
}

module "ansible" {
  count  = local.deploy_ansible ? 1 : 0
  source = "./modules/ansible"

  common_config          = local.common_config
  target_nodes_json      = jsonencode(local.all_ssh_nodes)
  admin_user_password    = var.admin_user_password
  admin_private_key_path = fileexists("./modules/ansible/ansible_admin_key") ? "./modules/ansible/ansible_admin_key" : ""
  mgmt_ip                = flatten(module.hammerspace[*].management_ip)
  anvil_instances        = flatten(module.hammerspace[*].anvil_instances)
  storage_instances      = flatten(module.storage_servers[*].instance_details)
  ecgroup_instances      = [for n in flatten(module.ecgroup[*].nodes) : n.name]
  ecgroup_nodes          = [for n in flatten(module.ecgroup[*].nodes) : n.private_ip]
  ecgroup_metadata_array = length(module.ecgroup) > 0 ? module.ecgroup[0].metadata_array : ""
  ecgroup_storage_array  = length(module.ecgroup) > 0 ? module.ecgroup[0].storage_array : ""

  instance_count          = var.ansible_instance_count
  image_id                = var.ansible_image_id
  shape                   = var.ansible_instance_shape
  ocpus                   = var.ansible_ocpus
  memory_in_gbs           = var.ansible_memory_gbs
  boot_volume_size        = var.ansible_boot_volume_size
  boot_volume_type        = var.ansible_boot_volume_type
  user_data               = var.ansible_user_data
  target_user             = var.ansible_target_user
  volume_group_name       = var.volume_group_name
  share_name              = var.share_name
  capacity_reservation_id = null # Disabled capacity reservations

  depends_on = [
    module.clients,
    module.storage_servers,
    module.hammerspace,
    module.ecgroup
  ]
}
