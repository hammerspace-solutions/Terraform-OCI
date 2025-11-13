# modules/clients/examples/main.tf

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Input variables for the example
variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user account"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the public key"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN"
  type        = string
}

variable "subnet_id" {
  description = "OCID of the subnet"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "clients_image_id" {
  description = "OCID of the image for client instances"
  type        = string
}

variable "clients_instance_shape" {
  description = "Instance shape for clients"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "clients_instance_count" {
  description = "Number of client instances"
  type        = number
  default     = 1
}

variable "block_volume_count" {
  description = "Number of block volumes per instance"
  type        = number
  default     = 1
}

variable "boot_volume_type" {
  description = "Boot volume attachment type"
  type        = string
  default     = "paravirtualized"
}

variable "block_volume_type" {
  description = "Block volume attachment type"
  type        = string
  default     = "paravirtualized"
}

variable "ad_number" {
  description = "Availability Domain number"
  type        = number
  default     = 1
}

# Data sources
data "oci_identity_availability_domain" "selected" {
  compartment_id = var.compartment_ocid
  ad_number      = var.ad_number
}

data "oci_core_subnet" "test_subnet" {
  subnet_id = var.subnet_id
}

# This module block calls the clients module for testing
module "clients" {
  source = "../" # Points to the parent 'clients' module directory

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

  # Client-specific configuration
  instance_count          = var.clients_instance_count
  image_id                = var.clients_image_id
  shape                   = var.clients_instance_shape
  ocpus                   = 2
  memory_in_gbs           = 32
  boot_volume_size        = 50
  boot_volume_type        = var.boot_volume_type
  block_volume_count      = var.block_volume_count
  block_volume_size       = 100
  block_volume_type       = var.block_volume_type
  block_volume_throughput = null
  block_volume_iops       = null
  user_data               = ""
  target_user             = "opc"

  # No capacity reservation for this test
  capacity_reservation_id = null
}

# Output the results for validation
output "client_instances" {
  description = "The details of the created client instances"
  value       = module.clients.instance_details
}

output "region" {
  description = "The OCI region where resources were deployed"
  value       = var.region
}

output "availability_domain" {
  description = "The availability domain where resources were deployed"
  value       = data.oci_identity_availability_domain.selected.name
}

output "instance_ids" {
  description = "List of instance OCIDs"
  value       = module.clients.instance_ids
}

output "network_security_group_id" {
  description = "Network Security Group OCID"
  value       = module.clients.network_security_group_id
}
