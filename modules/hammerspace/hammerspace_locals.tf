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
# modules/hammerspace/locals.tf
#
# This file contains the local variables and complex logic for the
# OCI Hammerspace module (Standalone only).
# -----------------------------------------------------------------------------

locals {
  # --- Anvil Creation Logic (Standalone only) ---
  should_create_any_anvils = var.anvil_count > 0

  # --- General Conditions ---
  dsx_add_volumes_bool = local.should_create_any_anvils && var.dsx_add_vols

  # --- Common Tags ---
  common_tags = var.common_config.tags

  # --- Shape Configuration ---
  # Check if shapes are Flex
  anvil_is_flex_shape = can(regex("Flex$", var.anvil_shape))
  dsx_is_flex_shape   = can(regex("Flex$", var.dsx_shape))

  # --- Security Group Selection Logic ---
  effective_anvil_sg_id = var.anvil_security_group_id != "" ? var.anvil_security_group_id : (length(oci_core_network_security_group.anvil_data_nsg) > 0 ? oci_core_network_security_group.anvil_data_nsg[0].id : null)
  effective_dsx_sg_id   = var.dsx_security_group_id != "" ? var.dsx_security_group_id : (length(oci_core_network_security_group.dsx_nsg) > 0 ? oci_core_network_security_group.dsx_nsg[0].id : null)

  # --- IP and ID Discovery for OCI ---
  management_ip_for_url = var.use_existing_anvil ? var.existing_anvil_ips[0] : (length(oci_core_instance.anvil) > 0 ? oci_core_instance.anvil[0].private_ip : "N/A - Anvil instance details not available.")

  effective_anvil_ip_for_dsx_metadata = length(oci_core_instance.anvil) > 0 ? oci_core_instance.anvil[0].private_ip : null

  effective_anvil_id_for_dsx_password = length(oci_core_instance.anvil) > 0 ? oci_core_instance.anvil[0].id : null


  anvil_nodes_map_for_dsx = var.anvil_count > 0 ? {
    "1" = { hostname = "${var.common_config.project_name}Anvil", features = ["metadata"] }
  } : {}

  # --- Resource Naming ---
  resource_prefix_anvil = "${var.common_config.project_name}-anvil"
  resource_prefix_dsx   = "${var.common_config.project_name}-dsx"

  # --- Port Configuration for OCI Network Security Groups ---
  anvil_tcp_ports = [22, 80, 111, 161, 443, 662, 2049, 2224, 4379, 8443, 9097, 9099, 9399, 20048, 20491, 20492, 21064, 50000, 51000, 53030]
  anvil_tcp_port_ranges = [
    { min = 4505, max = 4506 },
    { min = 7789, max = 7790 },
    { min = 9093, max = 9094 },
    { min = 9298, max = 9299 },
    { min = 41001, max = 41256 },
    { min = 52000, max = 52008 },
    { min = 53000, max = 53008 }
  ]
  anvil_udp_ports = [111, 123, 161, 662, 4379, 5405, 20048]

  dsx_tcp_ports = [22, 111, 139, 161, 445, 662, 2049, 3049, 4379, 9093, 9292, 20048, 20491, 20492, 30048, 30049, 50000, 51000, 53030]
  dsx_tcp_port_ranges = [
    { min = 4505, max = 4506 },
    { min = 9000, max = 9009 },
    { min = 9095, max = 9096 },
    { min = 9098, max = 9099 },
    { min = 41001, max = 41256 },
    { min = 52000, max = 52008 },
    { min = 53000, max = 53008 }
  ]
  dsx_udp_ports = [111, 161, 662, 20048, 30048, 30049]
}
