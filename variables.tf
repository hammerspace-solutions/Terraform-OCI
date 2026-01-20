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
# variables.tf
#
# This file defines all the input variables for the root module of the
# Terraform-OCI project.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OCI Authentication Variables
# -----------------------------------------------------------------------------
variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user account"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the public key associated with the user"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
}

# -----------------------------------------------------------------------------
# Global Infrastructure Variables
# -----------------------------------------------------------------------------
variable "region" {
  description = "OCI region for all resources"
  type        = string
  default     = "uk-london-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "vcn_id" {
  description = "OCID of an existing VCN. If not provided, a new VCN will be created"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "OCID of an existing subnet. If not provided, a new subnet will be created"
  type        = string
  default     = ""
}

variable "create_networking" {
  description = "Whether to create new VCN and subnet if not provided"
  type        = bool
  default     = true
}

variable "vcn_cidr" {
  description = "CIDR block for the new VCN (only used if creating new VCN)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the new subnet (only used if creating new subnet)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ad_number" {
  description = "Availability Domain number (1, 2, or 3)"
  type        = number
  default     = 1
  validation {
    condition     = var.ad_number >= 1 && var.ad_number <= 3
    error_message = "Availability Domain number must be 1, 2, or 3."
  }
}

variable "fault_domain" {
  description = "Fault domain name for instance placement (optional). Used for non-Anvil instances."
  type        = string
  default     = ""
}

variable "anvil_fault_domains" {
  description = "List of fault domains for Anvil instances. First element for primary (mds0), second for secondary (mds1). Example: [\"FAULT-DOMAIN-1\", \"FAULT-DOMAIN-2\"]"
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.anvil_fault_domains) == 0 || length(var.anvil_fault_domains) <= 3
    error_message = "anvil_fault_domains must be empty or contain up to 3 fault domain names."
  }
}

variable "assign_public_ip" {
  description = "If true, assigns a public IP address to all created compute instances"
  type        = bool
  default     = false
}

variable "nat_gateway_id" {
  description = "OCID of an existing NAT gateway to use when assign_public_ip is false. Required for hammerspace_anvil_count=2 with no public IPs"
  type        = string
  default     = ""
}

variable "create_nat_gateway_for_existing_vcn" {
  description = "Create a new NAT gateway in existing VCN when nat_gateway_id is not provided"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "project_name" {
  description = "Project name for tagging and resource naming"
  type        = string
  default     = ""
  validation {
    condition     = var.project_name != ""
    error_message = "Project must have a name"
  }
}

variable "deployment_name" {
  description = "The name of the deployment and VM instance."
  type        = string
  default     = "hammerspace-tf"
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH keys"
  type        = string
  default     = "./ssh_keys"
}

variable "deploy_components" {
  description = "Components to deploy. Valid values: \"all\", \"clients\", \"storage\", \"hammerspace\", \"ecgroup\", \"ansible\", \"bastion\"."
  type        = list(string)
  default     = ["all"]
  validation {
    condition = alltrue([
      for c in var.deploy_components : contains(["all", "clients", "storage", "hammerspace", "ecgroup", "ansible", "bastion"], c)
    ])
    error_message = "Each item in deploy_components must be one of: \"all\", \"ansible\", \"bastion\", \"clients\", \"storage\", \"ecgroup\" or \"hammerspace\"."
  }
}

# -----------------------------------------------------------------------------
# CLIENT-SPECIFIC VARIABLES
# -----------------------------------------------------------------------------
variable "clients_instance_count" {
  description = "Number of client instances"
  type        = number
  default     = 1
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

variable "clients_ocpus" {
  description = "Number of OCPUs for client instances (for Flex shapes)"
  type        = number
  default     = 8
}

variable "clients_memory_gbs" {
  description = "Amount of memory in GBs for client instances (for Flex shapes)"
  type        = number
  default     = 128
}

variable "clients_boot_volume_size" {
  description = "Boot volume size (GB) for clients"
  type        = number
  default     = 50
}

variable "clients_boot_volume_type" {
  description = "Boot volume attachment type for clients (iscsi or paravirtualized)"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.clients_boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "clients_block_volume_count" {
  description = "Number of extra block volumes per client"
  type        = number
  default     = 2
}

variable "clients_block_volume_size" {
  description = "Size of each block volume (GB) for clients"
  type        = number
  default     = 100
}

variable "clients_block_volume_type" {
  description = "Type of block volume attachment for clients (iscsi or paravirtualized)"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.clients_block_volume_type)
    error_message = "Block volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "clients_block_volume_throughput" {
  description = "Throughput for block volumes for clients (MB/s) - for performance tiers"
  type        = number
  default     = null
}

variable "clients_block_volume_iops" {
  description = "IOPS for block volumes for clients - for performance tiers"
  type        = number
  default     = null
}

variable "clients_user_data" {
  description = "Cloud-init user data script for clients"
  type        = string
  default     = ""
}

variable "clients_target_user" {
  description = "Default system user for client instances"
  type        = string
  default     = "opc"
}

# -----------------------------------------------------------------------------
# STORAGE-SPECIFIC VARIABLES
# -----------------------------------------------------------------------------
variable "storage_instance_count" {
  description = "Number of storage instances"
  type        = number
  default     = 1
}

variable "storage_image_id" {
  description = "OCID of the image for storage instances"
  type        = string
}

variable "storage_instance_shape" {
  description = "Instance shape for storage"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "storage_ocpus" {
  description = "Number of OCPUs for storage instances (for Flex shapes)"
  type        = number
  default     = 8
}

variable "storage_memory_gbs" {
  description = "Amount of memory in GBs for storage instances (for Flex shapes)"
  type        = number
  default     = 128
}

variable "storage_boot_volume_size" {
  description = "Boot volume size (GB) for storage"
  type        = number
  default     = 100
}

variable "storage_boot_volume_type" {
  description = "Boot volume attachment type for storage (iscsi or paravirtualized)"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.storage_boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "storage_block_volume_count" {
  description = "Number of extra block volumes per storage instance"
  type        = number
  default     = 2
}

variable "storage_block_volume_size" {
  description = "Size of each block volume (GB) for storage"
  type        = number
  default     = 200
}

variable "storage_block_volume_type" {
  description = "Type of block volume attachment for storage (iscsi or paravirtualized)"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.storage_block_volume_type)
    error_message = "Block volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "storage_block_volume_throughput" {
  description = "Throughput for block volumes for storage (MB/s) - for performance tiers"
  type        = number
  default     = null
}

variable "storage_block_volume_iops" {
  description = "IOPS for block volumes for storage - for performance tiers"
  type        = number
  default     = null
}

variable "storage_user_data" {
  description = "Cloud-init user data script for storage"
  type        = string
  default     = ""
}

variable "storage_target_user" {
  description = "Default system user for storage instances"
  type        = string
  default     = "opc"
}

variable "storage_raid_level" {
  description = "RAID level to configure for storage servers (raid-0, raid-5, or raid-6)"
  type        = string
  default     = "raid-0"
  validation {
    condition     = contains(["raid-0", "raid-5", "raid-6"], var.storage_raid_level)
    error_message = "RAID level must be one of: raid-0, raid-5, or raid-6"
  }
}

# -----------------------------------------------------------------------------
# HAMMERSPACE-SPECIFIC VARIABLES
# -----------------------------------------------------------------------------
variable "hammerspace_image_id" {
  description = "OCID of the image for Hammerspace instances (fallback if anvil/dsx specific images not set)"
  type        = string
  default     = ""
}

variable "hammerspace_anvil_image_id" {
  description = "OCID of the image for Anvil (MDS) instances. If not specified, falls back to hammerspace_image_id."
  type        = string
  default     = ""
}

variable "hammerspace_dsx_image_id" {
  description = "OCID of the image for DSX instances. If not specified, falls back to hammerspace_image_id."
  type        = string
  default     = ""
}

variable "hammerspace_profile_id" {
  description = "The name of an existing IAM Instance Profile (if applicable for custom setups)"
  type        = string
  default     = ""
}

variable "hammerspace_anvil_security_group_id" {
  description = "Optional: An existing security group OCID to use for the Anvil nodes"
  type        = string
  default     = ""
}

variable "hammerspace_dsx_security_group_id" {
  description = "Optional: An existing security group OCID to use for the DSX nodes"
  type        = string
  default     = ""
}

variable "hammerspace_anvil_count" {
  description = "Number of Anvil instances to deploy (0=none, 1=standalone)"
  type        = number
  default     = 0
  validation {
    condition     = var.hammerspace_anvil_count >= 0 && var.hammerspace_anvil_count <= 2
    error_message = "Anvil count must be 0 (none) or 1 (standalone)"
  }
}

variable "hammerspace_sa_anvil_destruction" {
  description = "Safety switch to allow destruction of Anvil"
  type        = bool
  default     = false
}

variable "hammerspace_anvil_instance_shape" {
  description = "Instance shape for Anvil metadata server"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "hammerspace_anvil_ocpus" {
  description = "Number of OCPUs for Anvil instances (for Flex shapes)"
  type        = number
  default     = 12
}

variable "hammerspace_anvil_memory_gbs" {
  description = "Amount of memory in GBs for Anvil instances (for Flex shapes)"
  type        = number
  default     = 192
}

variable "hammerspace_dsx_instance_shape" {
  description = "Instance shape for DSX nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "hammerspace_dsx_ocpus" {
  description = "Number of OCPUs for DSX instances (for Flex shapes)"
  type        = number
  default     = 2
}

variable "hammerspace_dsx_memory_gbs" {
  description = "Amount of memory in GBs for DSX instances (for Flex shapes)"
  type        = number
  default     = 32
}

variable "hammerspace_dsx_count" {
  description = "Number of DSX instances"
  type        = number
  default     = 1
}

variable "hammerspace_anvil_enable_sriov" {
  description = "Enable SR-IOV (VFIO) networking for Anvil instances. Requires compatible shape and image."
  type        = bool
  default     = false
}

variable "hammerspace_dsx_enable_sriov" {
  description = "Enable SR-IOV (VFIO) networking for DSX instances. Requires compatible shape and image."
  type        = bool
  default     = false
}

variable "hammerspace_anvil_meta_disk_size" {
  description = "Metadata disk size in GB for Anvil"
  type        = number
  default     = 100
}

variable "hammerspace_anvil_meta_disk_type" {
  description = "Type of block volume attachment for Anvil metadata disk"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.hammerspace_anvil_meta_disk_type)
    error_message = "Anvil meta disk type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "hammerspace_anvil_meta_disk_throughput" {
  description = "Throughput for Anvil metadata disk (MB/s) - for performance tiers"
  type        = number
  default     = null
}

variable "hammerspace_anvil_meta_disk_iops" {
  description = "IOPS for Anvil metadata disk - for performance tiers"
  type        = number
  default     = null
}

variable "hammerspace_dsx_block_volume_size" {
  description = "Size of each data volume per DSX node in GB"
  type        = number
  default     = 100
}

variable "hammerspace_dsx_block_volume_type" {
  description = "Type of block volume attachment for DSX data volumes"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.hammerspace_dsx_block_volume_type)
    error_message = "DSX block volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "hammerspace_dsx_block_volume_iops" {
  description = "IOPS for each DSX data volume - for performance tiers"
  type        = number
  default     = null
}

variable "hammerspace_dsx_block_volume_throughput" {
  description = "Throughput for each DSX data volume (MB/s) - for performance tiers"
  type        = number
  default     = null
}

variable "hammerspace_dsx_block_volume_count" {
  description = "Number of data block volumes to attach to each DSX instance"
  type        = number
  default     = 1
}

variable "hammerspace_dsx_add_vols" {
  description = "Add non-boot block volumes as Hammerspace storage volumes"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ECGROUP-SPECIFIC VARIABLES
# -----------------------------------------------------------------------------
variable "ecgroup_instance_shape" {
  description = "Instance shape for ECGroup nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ecgroup_ocpus" {
  description = "Number of OCPUs for ECGroup instances (for Flex shapes)"
  type        = number
  default     = 16
}

variable "ecgroup_memory_gbs" {
  description = "Amount of memory in GBs for ECGroup instances (for Flex shapes)"
  type        = number
  default     = 256
}

variable "ecgroup_node_count" {
  description = "Number of ECGroup nodes to create"
  type        = number
  default     = 0
}

variable "ecgroup_image_id" {
  description = "OCID of the image for ECGroup instances (fallback if region mapping fails)"
  type        = string
  default     = ""
}

variable "ecgroup_boot_volume_size" {
  description = "Boot volume size (GB) for ECGroup nodes"
  type        = number
  default     = 100
}

variable "ecgroup_boot_volume_type" {
  description = "Boot volume attachment type for ECGroup nodes"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.ecgroup_boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "ecgroup_metadata_volume_size" {
  description = "Size of the ECGroup metadata block volume in GB"
  type        = number
  default     = 50
}

variable "ecgroup_metadata_volume_type" {
  description = "Type of block volume attachment for ECGroup metadata"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.ecgroup_metadata_volume_type)
    error_message = "Metadata volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "ecgroup_metadata_volume_throughput" {
  description = "Throughput for metadata block volumes for ECGroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "ecgroup_metadata_volume_iops" {
  description = "IOPS for metadata block volumes for ECGroup nodes"
  type        = number
  default     = null
}

variable "ecgroup_storage_volume_count" {
  description = "Number of ECGroup storage volumes to attach to each node"
  type        = number
  default     = 0
}

variable "ecgroup_storage_volume_size" {
  description = "Size of each storage block volume (GB) for ECGroup nodes"
  type        = number
  default     = 0
}

variable "ecgroup_storage_volume_type" {
  description = "Type of block volume attachment for ECGroup storage"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.ecgroup_storage_volume_type)
    error_message = "Storage volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "ecgroup_storage_volume_throughput" {
  description = "Throughput for each storage block volume for ECGroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "ecgroup_storage_volume_iops" {
  description = "IOPS for each storage block volume for ECGroup nodes"
  type        = number
  default     = null
}

variable "ecgroup_user_data" {
  description = "Cloud-init user data script for ECGroup"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# ANSIBLE-SPECIFIC VARIABLES
# -----------------------------------------------------------------------------
variable "ansible_instance_count" {
  description = "Number of Ansible instances"
  type        = number
  default     = 1
}

variable "ansible_image_id" {
  description = "OCID of the image for Ansible instances"
  type        = string
}

variable "ansible_instance_shape" {
  description = "Instance shape for Ansible"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ansible_ocpus" {
  description = "Number of OCPUs for Ansible instances (for Flex shapes)"
  type        = number
  default     = 8
}

variable "ansible_memory_gbs" {
  description = "Amount of memory in GBs for Ansible instances (for Flex shapes)"
  type        = number
  default     = 128
}

variable "ansible_boot_volume_size" {
  description = "Boot volume size (GB) for Ansible"
  type        = number
  default     = 100
}

variable "ansible_boot_volume_type" {
  description = "Boot volume attachment type for Ansible"
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.ansible_boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "ansible_user_data" {
  description = "Cloud-init user data script for Ansible"
  type        = string
  default     = ""
}

variable "ansible_target_user" {
  description = "Default system user for Ansible instances"
  type        = string
  default     = "opc"
}

variable "volume_group_name" {
  description = "Volume group name for storage servers"
  type        = string
  default     = "vg-auto"
}

variable "share_name" {
  description = "Share name for storage servers"
  type        = string
  default     = ""
}

variable "ecgroup_add_to_hammerspace" {
  description = "Whether to add ECGroup to Hammerspace as a storage node"
  type        = bool
  default     = false
}

variable "ecgroup_volume_group_name" {
  description = "Volume group name for ECGroup (only used if ecgroup_add_to_hammerspace is true)"
  type        = string
  default     = ""
}

variable "ecgroup_share_name" {
  description = "Share name for ECGroup (only used if ecgroup_add_to_hammerspace is true)"
  type        = string
  default     = ""
}

variable "add_storage_server_volumes" {
  description = "Whether to add storage server volumes to Hammerspace"
  type        = bool
  default     = true
}

variable "add_ecgroup_volumes" {
  description = "Whether to add ECGroup volumes to Hammerspace (only applies if ecgroup_add_to_hammerspace is true)"
  type        = bool
  default     = true
}


variable "api_key" {
  description = "OCI generated API key"
  type        = string
  default     = "oci/oci_api_key.pem"
}

variable "config_file" {
  description = "OCI generated config file"
  type        = string
  default     = "oci/config"
}

variable "oci_cli_rc" {
  description = "OCI CLI RC file (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "admin_user_password" {
  description = "Password for the admin user"
  type        = string
}

variable "domainname" {
  description = "Domain name for the deployment"
  type        = string
  default     = "localdomain"
}

# -----------------------------------------------------------------------------
# Bastion Module Variables
# -----------------------------------------------------------------------------
variable "bastion_instance_count" {
  description = "Number of bastion instances to create"
  type        = number
  default     = 1
}

variable "bastion_image_id" {
  description = "OCID of the image for bastion instances"
  type        = string
}

variable "bastion_instance_shape" {
  description = "Shape for bastion instances"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "bastion_ocpus" {
  description = "Number of OCPUs for bastion instances (for flexible shapes)"
  type        = number
  default     = 2
}

variable "bastion_memory_gbs" {
  description = "Memory in GBs for bastion instances (for flexible shapes)"
  type        = number
  default     = 16
}

variable "bastion_boot_volume_size" {
  description = "Boot volume size in GBs for bastion instances"
  type        = number
  default     = 50
}

variable "bastion_boot_volume_type" {
  description = "Boot volume attachment type for bastion instances"
  type        = string
  default     = "paravirtualized"
}

variable "bastion_user_data" {
  description = "Path to cloud-init user data script for bastion instances"
  type        = string
  default     = ""
}

variable "bastion_target_user" {
  description = "Default system user for bastion instances"
  type        = string
  default     = "ubuntu"
}

variable "bastion_allowed_source_cidr_blocks" {
  description = "List of CIDR blocks allowed to access bastion instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Variables for existing infrastructure ---

variable "hammerspace_use_existing_anvil" {
  description = "Whether to use existing Anvil instances instead of deploying new ones"
  type        = bool
  default     = false
}

variable "hammerspace_existing_anvil_ips" {
  description = "IP addresses of existing Anvil instances (required if hammerspace_use_existing_anvil = true)"
  type        = list(string)
  default     = []
}

variable "hammerspace_existing_anvil_password" {
  description = "Admin password for existing Anvil instances (required if hammerspace_use_existing_anvil = true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "hammerspace_use_existing_dsx" {
  description = "Whether to use existing DSX instances instead of deploying new ones"
  type        = bool
  default     = false
}

variable "hammerspace_existing_dsx_ips" {
  description = "IP addresses of existing DSX instances (required if hammerspace_use_existing_dsx = true)"
  type        = list(string)
  default     = []
}


