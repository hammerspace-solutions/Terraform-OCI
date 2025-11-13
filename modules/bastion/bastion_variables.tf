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
# modules/bastion/bastion_variables.tf
#
# This file defines all the input variables for the Bastion client module.
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
    fault_domain        = string
  })
}

variable "allowed_source_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the bastion instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type        = string
  default     = null
}


# --- Bastion-specific variables ---

variable "instance_count" {
  description = "Number of bastion instances"
  type        = number
}

variable "image_id" {
  description = "OCID of the image for the bastion instances"
  type        = string
}

variable "shape" {
  description = "Shape for the bastion instances"
  type        = string
}

variable "ocpus" {
  description = "Number of OCPUs for flexible shapes"
  type        = number
  default     = 1
}

variable "memory_in_gbs" {
  description = "Memory in GBs for flexible shapes"
  type        = number
  default     = 8
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for the bastion client"
  type        = number
}

variable "boot_volume_type" {
  description = "Boot volume attachment type (paravirtualized or iscsi)"
  type        = string
  default     = "paravirtualized"
}

variable "user_data" {
  description = "Path to user data script for the bastion instances"
  type        = string
  default     = ""
}

variable "target_user" {
  description = "Default system user for the bastion client EC2s"
  type        = string
}
