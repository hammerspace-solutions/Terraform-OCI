# modules/bastion/examples/main.tf

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# These are the variables that the test will provide values for.
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}
variable "compartment_ocid" {}
variable "project_name" {}
variable "vcn_id" {}
variable "subnet_id" {}
variable "ssh_public_key" {}
variable "ad_number" {
  type    = number
  default = 1
}
variable "bastion_image_id" {}
variable "bastion_instance_shape" {
  default = "VM.Standard.E4.Flex"
}
variable "bastion_instance_count" {
  type    = number
  default = 1
}
variable "boot_volume_type" {
  type    = string
  default = "paravirtualized"
}

# Look up the availability domain
data "oci_identity_availability_domain" "selected" {
  compartment_id = var.compartment_ocid
  ad_number      = var.ad_number
}


# This module block calls the bastion module for testing.
module "bastion" {
  source = "../" # Points to the parent 'bastion' module directory

  # Common configuration
  common_config = {
    region              = var.region
    availability_domain = data.oci_identity_availability_domain.selected.name
    compartment_id      = var.compartment_ocid
    vcn_id              = var.vcn_id
    subnet_id           = var.subnet_id
    ssh_public_key      = var.ssh_public_key
    tags                = { Environment = "test" }
    project_name        = var.project_name
    assign_public_ip    = true
    ssh_keys_dir        = ""
    fault_domain        = null
  }

  # Bastion-specific configuration
  instance_count          = var.bastion_instance_count
  image_id                = var.bastion_image_id
  shape                   = var.bastion_instance_shape
  ocpus                   = 1
  memory_in_gbs           = 8
  boot_volume_size        = 50
  boot_volume_type        = var.boot_volume_type
  user_data               = ""
  target_user             = "ubuntu"
  allowed_source_cidr_blocks = ["0.0.0.0/0"]

  # For this isolated test, we do not use a capacity reservation.
  capacity_reservation_id = null
}


# Output the results for validation by the Go test.
output "bastion_instances" {
  description = "The details of the created bastion instances."
  value       = module.bastion.instance_details
}

output "region" {
  description = "The OCI region where resources were deployed."
  value       = var.region
}
