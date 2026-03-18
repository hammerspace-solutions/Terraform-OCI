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
# modules/clients/variables.tf
#
# This file defines all the input variables for the OCI Clients module.
# -----------------------------------------------------------------------------

variable "common_config" {
  description = "A map containing common configuration values like region, VCN, subnet, etc."
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

variable "capacity_reservation_id" {
  description = "The OCID of the Compute Capacity Reservation to target."
  type        = string
  default     = null
}

# --- Client-specific variables ---

variable "instance_count" {
  description = "Number of client instances"
  type        = number
}

variable "image_id" {
  description = "OCID of the image for client instances"
  type        = string
}

variable "shape" {
  description = "Instance shape for clients"
  type        = string
}

variable "ocpus" {
  description = "Number of OCPUs for client instances (for Flex shapes)"
  type        = number
  default     = 8
}

variable "memory_in_gbs" {
  description = "Amount of memory in GBs for client instances (for Flex shapes)"
  type        = number
  default     = 128
}

variable "boot_volume_size" {
  description = "Boot volume size (GB) for clients"
  type        = number
}

variable "boot_volume_type" {
  description = "Boot volume attachment type for clients (iscsi or paravirtualized)"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "block_volume_count" {
  description = "Number of extra block volumes per client"
  type        = number
}

variable "block_volume_size" {
  description = "Size of each block volume (GB) for clients"
  type        = number
}

variable "block_volume_type" {
  description = "Type of block volume attachment for clients (iscsi or paravirtualized)"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.block_volume_type)
    error_message = "Block volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "block_volume_throughput" {
  description = "Throughput for block volumes for clients (MB/s) - for performance tiers"
  type        = number
  default     = null
}

variable "block_volume_iops" {
  description = "IOPS for block volumes for clients - for performance tiers"
  type        = number
  default     = null
}

variable "user_data" {
  description = "Cloud-init user data script for clients"
  type        = string
}

variable "target_user" {
  description = "Default system user for client instances"
  type        = string
}
