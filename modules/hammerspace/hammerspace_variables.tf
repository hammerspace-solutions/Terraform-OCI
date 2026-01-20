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
# modules/hammerspace/variables.tf
#
# This file defines all the input variables for the OCI Hammerspace module.
# -----------------------------------------------------------------------------

variable "common_config" {
  description = "A map containing common configuration values like region, availability domain, compartment, etc."
  type = object({
    region              = string
    availability_domain = string
    compartment_id      = string
    vcn_id              = string
    subnet_id           = string
    ssh_public_key      = string
    tags                = map(string)
    project_name        = string
    assign_public_ip    = bool
    ssh_keys_dir        = string
    fault_domain        = optional(string)
  })
}

variable "anvil_fault_domains" {
  description = "List of fault domains for Anvil instances. First element for primary (mds0), second for secondary (mds1). Example: [\"FAULT-DOMAIN-1\", \"FAULT-DOMAIN-2\"]"
  type        = list(string)
  default     = []
}

variable "anvil_capacity_reservation_id" {
  description = "The OCID of the Compute Capacity Reservation to target for Anvil nodes."
  type        = string
  default     = null
}

variable "dsx_capacity_reservation_id" {
  description = "The OCID of the Compute Capacity Reservation to target for DSX nodes."
  type        = string
  default     = null
}

# --- Hammerspace-specific variables ---

variable "image_id" {
  description = "OCID of the image to use for Hammerspace instances (used as fallback if anvil_image_id or dsx_image_id not specified)."
  type        = string
  default     = ""
}

variable "anvil_image_id" {
  description = "OCID of the image to use for Anvil (MDS) instances. If not specified, falls back to image_id."
  type        = string
  default     = ""
}

variable "dsx_image_id" {
  description = "OCID of the image to use for DSX instances. If not specified, falls back to image_id."
  type        = string
  default     = ""
}

variable "profile_id" {
  description = "Existing Instance Principal or Dynamic Group name (optional). If blank, default instance principal is used."
  type        = string
  default     = ""
}

variable "anvil_security_group_id" {
  description = "Optional: The OCID of an existing network security group to use for the Anvil nodes. If provided, the module will not create a new one."
  type        = string
  default     = ""
}

variable "dsx_security_group_id" {
  description = "Optional: The OCID of an existing network security group to use for the DSX nodes. If provided, the module will not create a new one."
  type        = string
  default     = ""
}

variable "anvil_count" {
  description = "Number of Anvil instances to deploy. 0 = no Anvils; 1 = Standalone. (Ignored if use_existing_anvil = true)"
  type        = number
  default     = 1
  validation {
    condition     = var.anvil_count >= 0 && var.anvil_count <= 2
    error_message = "Anvil count must be 0 (none) or 1 (standalone)"
  }
}

variable "sa_anvil_destruction" {
  description = "Set to true to allow the Anvil to be destroyed. This is a safety mechanism to prevent accidental destruction."
  type        = bool
  default     = false
}

variable "anvil_shape" {
  description = "OCI instance shape for Anvil metadata servers (e.g., 'VM.Standard.E5.Flex')."
  type        = string
  default     = "VM.Standard.E5.Flex"
}

variable "anvil_ocpus" {
  description = "Number of OCPUs for Anvil instances (for Flex shapes)"
  type        = number
  default     = 12
}

variable "anvil_memory_in_gbs" {
  description = "Amount of memory in GBs for Anvil instances (for Flex shapes)"
  type        = number
  default     = 192
}

variable "dsx_shape" {
  description = "OCI instance shape for DSX data services nodes (e.g., 'VM.Standard.E5.Flex')."
  type        = string
  default     = "VM.Standard.E5.Flex"
}

variable "dsx_ocpus" {
  description = "Number of OCPUs for DSX instances (for Flex shapes)"
  type        = number
  default     = 2
}

variable "dsx_memory_in_gbs" {
  description = "Amount of memory in GBs for DSX instances (for Flex shapes)"
  type        = number
  default     = 32
}

variable "dsx_count" {
  description = "Number of DSX instances to create (0-8)."
  type        = number
  default     = 1
}

variable "anvil_enable_sriov" {
  description = "Enable SR-IOV (VFIO) networking for Anvil instances."
  type        = bool
  default     = false
}

variable "dsx_enable_sriov" {
  description = "Enable SR-IOV (VFIO) networking for DSX instances."
  type        = bool
  default     = false
}

variable "anvil_meta_disk_size" {
  description = "Anvil Metadata Disk Size in GB."
  type        = number
  default     = 1000
}

variable "anvil_meta_disk_type" {
  description = "Anvil Metadata Disk attachment type ('iscsi' or 'paravirtualized')."
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.anvil_meta_disk_type)
    error_message = "Anvil meta disk type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "anvil_meta_disk_iops" {
  description = "IOPS for Anvil metadata disk (for high performance volumes)."
  type        = number
  default     = null
}

variable "anvil_meta_disk_throughput" {
  description = "Throughput in MB/s for Anvil metadata disk (for high performance volumes)."
  type        = number
  default     = null
}

variable "dsx_block_volume_size" {
  description = "Size of each block volume per DSX instance in GB."
  type        = number
  default     = 200
}

variable "dsx_block_volume_type" {
  description = "Type of block volume attachment for DSX ('iscsi' or 'paravirtualized')."
  type        = string
  default     = "paravirtualized"
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.dsx_block_volume_type)
    error_message = "DSX block volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "dsx_block_volume_iops" {
  description = "IOPS for each DSX block volume (for high performance volumes)."
  type        = number
  default     = null
}

variable "dsx_block_volume_throughput" {
  description = "Throughput in MB/s for each DSX block volume (for high performance volumes)."
  type        = number
  default     = null
}

variable "dsx_block_volume_count" {
  description = "Number of data block volumes to attach to each DSX instance."
  type        = number
  default     = 1
  validation {
    condition     = var.dsx_block_volume_count >= 0
    error_message = "The number of data block volumes per DSX instance must be non-negative."
  }
  validation {
    condition     = var.dsx_count == 0 || var.dsx_block_volume_count >= 1
    error_message = "If dsx_count is greater than 0, dsx_block_volume_count must be at least 1."
  }
}

variable "dsx_add_vols" {
  description = "Add non-boot block volumes as Hammerspace storage volumes."
  type        = bool
  default     = true
}

variable "sec_ip_cidr" {
  description = "Permitted IP/CIDR for Security Group Ingress. Use '0.0.0.0/0' for open access (not recommended for production)."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(regex("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:3[0-2]|[12]?[0-9]?)$", var.sec_ip_cidr))
    error_message = "Security IP CIDR must be a valid CIDR block."
  }
}

variable "deployment_name" {
  description = "The name of the deployment and VM instance."
  type        = string
  default     = "hammerspace-tf"
}

variable "api_key" {
  description = "OCI generated API key"
  type        = string
  default     = ""
}

variable "config_file" {
  description = "OCI generated config file"
  type        = string
  default     = ""
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

variable "nat_gateway_id" {
  description = "OCID of the NAT gateway for instances to access the internet when assign_public_ip is false"
  type        = string
  default     = ""
}

variable "anvil_network_interface_name" {
  description = "Network interface name for Anvil instances (ens3 for E2/E3/E4, enp0s5 for E5)"
  type        = string
  default     = ""
}

variable "dsx_network_interface_name" {
  description = "Network interface name for DSX instances (ens3 for E2/E3/E4, enp0s5 for E5)"
  type        = string
  default     = ""
}

# --- Variables for existing infrastructure ---

variable "use_existing_anvil" {
  description = "Whether to use existing Anvil instances instead of deploying new ones"
  type        = bool
  default     = false
}

variable "existing_anvil_ips" {
  description = "IP addresses of existing Anvil instances (required if use_existing_anvil = true)"
  type        = list(string)
  default     = []
  validation {
    condition     = !var.use_existing_anvil || length(var.existing_anvil_ips) > 0
    error_message = "existing_anvil_ips must be provided when use_existing_anvil is true"
  }
}

variable "existing_anvil_password" {
  description = "Admin password for existing Anvil instances (required if use_existing_anvil = true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_existing_dsx" {
  description = "Whether to use existing DSX instances instead of deploying new ones"
  type        = bool
  default     = false
}

variable "existing_dsx_ips" {
  description = "IP addresses of existing DSX instances (required if use_existing_dsx = true)"
  type        = list(string)
  default     = []
  validation {
    condition     = !var.use_existing_dsx || length(var.existing_dsx_ips) > 0
    error_message = "existing_dsx_ips must be provided when use_existing_dsx is true"
  }
}
