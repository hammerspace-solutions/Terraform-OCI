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
# modules/ecgroup/variables.tf
#
# This file defines all the input variables for the OCI ECGroup module.
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

variable "capacity_reservation_id" {
  description = "The OCID of the Compute Capacity Reservation to target."
  type        = string
  default     = null
}

# ECGroup specific variables
variable "shape" {
  description = "Instance shape for ECGroup nodes"
  type        = string
}

variable "ocpus" {
  description = "Number of OCPUs for ECGroup instances (for Flex shapes)"
  type        = number
  default     = 16
}

variable "memory_in_gbs" {
  description = "Amount of memory in GBs for ECGroup instances (for Flex shapes)"
  type        = number
  default     = 256
}

variable "node_count" {
  description = "Number of ECGroup node instances"
  type        = number
}

variable "image_id" {
  description = "OCID of the image for ECGroup instances"
  type        = string
}

variable "boot_volume_size" {
  description = "Boot volume size (GB) for ECGroup nodes"
  type        = number
}

variable "boot_volume_type" {
  description = "Boot volume attachment type for ECGroup nodes"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "metadata_block_size" {
  description = "Size of the metadata block volume (GB) for ECGroup nodes"
  type        = number
}

variable "metadata_block_type" {
  description = "Type of block volume attachment for ECGroup metadata"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.metadata_block_type)
    error_message = "Metadata block type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "metadata_block_throughput" {
  description = "Throughput for metadata block volumes for ECGroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "metadata_block_iops" {
  description = "IOPS for metadata block volumes for ECGroup nodes"
  type        = number
  default     = null
}

variable "storage_block_count" {
  description = "Number of storage block volumes per ECGroup node"
  type        = number
}

variable "storage_block_size" {
  description = "Size of each storage block volume (GB) for ECGroup nodes"
  type        = number
}

variable "storage_block_type" {
  description = "Type of block volume attachment for ECGroup storage"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.storage_block_type)
    error_message = "Storage block type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "storage_block_throughput" {
  description = "Throughput for each storage block volume for ECGroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "storage_block_iops" {
  description = "IOPS for each storage block volume for ECGroup nodes"
  type        = number
  default     = null
}

variable "user_data" {
  description = "Cloud-init user data script for ECGroup nodes"
  type        = string
}
