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
# modules/ansible/variables.tf
#
# This file defines all the input variables for the OCI Ansible module.
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

# --- Ansible-specific variables ---

variable "instance_count" {
  description = "Number of Ansible instances"
  type        = number
}

variable "image_id" {
  description = "OCID of the image for Ansible instances"
  type        = string
}

variable "shape" {
  description = "Instance shape for Ansible"
  type        = string
}

variable "ocpus" {
  description = "Number of OCPUs for Ansible instances (for Flex shapes)"
  type        = number
  default     = 8
}

variable "memory_in_gbs" {
  description = "Amount of memory in GBs for Ansible instances (for Flex shapes)"
  type        = number
  default     = 128
}

variable "boot_volume_size" {
  description = "Boot volume size (GB) for Ansible"
  type        = number
}

variable "boot_volume_type" {
  description = "Boot volume attachment type for Ansible (iscsi or paravirtualized)"
  type        = string
  validation {
    condition     = contains(["iscsi", "paravirtualized"], var.boot_volume_type)
    error_message = "Boot volume type must be either 'iscsi' or 'paravirtualized'."
  }
}

variable "user_data" {
  description = "Cloud-init user data script for Ansible"
  type        = string
}

variable "target_user" {
  description = "Default system user for Ansible instances"
  type        = string
}

# --- Ansible configuration variables ---

variable "target_nodes_json" {
  description = "A JSON-encoded string of all client and storage nodes for Ansible to configure."
  type        = string
  default     = "[]"
}

variable "admin_private_key_path" {
  description = "The local path to the private key for the Ansible controller"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Hammerspace variables ---

variable "mgmt_ip" {
  description = "Hammerspace management IP address"
  type        = list(string)
  default     = []
}

variable "anvil_instances" {
  description = "Anvil instances details"
  type = list(object({
    id         = string
    private_ip = string
    public_ip  = string
    name       = string
    shape      = string
    state      = string
  }))
  default = []
}

variable "storage_instances" {
  description = "Storage instances details"
  type = list(object({
    id         = string
    private_ip = string
    public_ip  = string
    name       = string
    shape      = string
    state      = string
  }))
  default = []
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

# --- ECGroup variables ---

variable "ecgroup_instances" {
  description = "ECGroup instance OCIDs"
  type        = list(string)
  default     = []
}

variable "ecgroup_nodes" {
  description = "ECGroup node IP addresses"
  type        = list(string)
  default     = []
}

variable "ecgroup_metadata_array" {
  description = "ECGroup metadata array information"
  type        = any
  default     = []
}

variable "ecgroup_storage_array" {
  description = "ECGroup storage array information"
  type        = any
  default     = []
}

variable "admin_user_password" {
  description = "Password for the admin user"
  type        = string
}
