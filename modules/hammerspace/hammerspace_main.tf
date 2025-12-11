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
# modules/hammerspace/main.tf
#
# This file contains the main logic for the OCI Hammerspace module. It creates
# all the necessary OCI resources for Anvil and DSX nodes (Standalone only).
# -----------------------------------------------------------------------------

# Local values for network interface names based on shape
locals {
  # Determine network interface name based on shape
  # E2/E3/E4 shapes use ens3, E5 shapes use enp0s5
  anvil_interface_name = var.anvil_network_interface_name != "" ? var.anvil_network_interface_name : (
    startswith(var.anvil_shape, "VM.Standard.E5") ? "enp0s5" : "ens3"
  )
  
  dsx_interface_name = var.dsx_network_interface_name != "" ? var.dsx_network_interface_name : (
    startswith(var.dsx_shape, "VM.Standard.E5") ? "enp0s5" : "ens3"
  )
}

# Data sources for validation
data "oci_core_shapes" "anvil_shapes" {
  count               = var.anvil_count > 0 ? 1 : 0
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.anvil_shape]
  }
}

data "oci_core_shapes" "dsx_shapes" {
  count               = var.dsx_count > 0 ? 1 : 0
  compartment_id      = var.common_config.compartment_id
  availability_domain = var.common_config.availability_domain

  filter {
    name   = "name"
    values = [var.dsx_shape]
  }
}

# NAT Gateway validation for Anvil instances when public IP is not assigned
check "anvil_nat_gateway_requirement" {
  assert {
    condition = !(var.anvil_count == 2 && !var.common_config.assign_public_ip && var.nat_gateway_id == "")
    error_message = "When anvil_count=2 and assign_public_ip=false, nat_gateway_id must be provided to ensure instances can access the internet for OCI CLI commands"
  }
}

# Removed the data source validation as it causes issues with dynamic count
# The NAT gateway existence will be validated at apply time

data "oci_core_image" "hammerspace_image" {
  image_id = var.image_id
}

# --- Network Security Groups ---
resource "oci_core_network_security_group" "anvil_data_nsg" {
  count          = var.anvil_count > 0 && var.anvil_security_group_id == "" ? 1 : 0
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix_anvil}-nsg"

  defined_tags  = local.common_tags
  freeform_tags = { Purpose = "Anvil-Data-Security" }
}

# Anvil NSG Rules - ICMP
resource "oci_core_network_security_group_security_rule" "anvil_ingress_icmp" {
  count                     = var.anvil_count > 0 && var.anvil_security_group_id == "" ? 1 : 0
  network_security_group_id = oci_core_network_security_group.anvil_data_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"
  description               = "ICMP traffic for Anvil nodes"
}

# Anvil NSG Rules - TCP Single Ports
resource "oci_core_network_security_group_security_rule" "anvil_ingress_tcp" {
  count                     = var.anvil_count > 0 && var.anvil_security_group_id == "" ? length(local.anvil_tcp_ports) : 0
  network_security_group_id = oci_core_network_security_group.anvil_data_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = local.anvil_tcp_ports[count.index]
      max = local.anvil_tcp_ports[count.index]
    }
  }

  description = "TCP port ${local.anvil_tcp_ports[count.index]} for Anvil nodes"
}

# Anvil NSG Rules - TCP Port Ranges
resource "oci_core_network_security_group_security_rule" "anvil_ingress_tcp_ranges" {
  count                     = var.anvil_count > 0 && var.anvil_security_group_id == "" ? length(local.anvil_tcp_port_ranges) : 0
  network_security_group_id = oci_core_network_security_group.anvil_data_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = local.anvil_tcp_port_ranges[count.index].min
      max = local.anvil_tcp_port_ranges[count.index].max
    }
  }

  description = "TCP ports ${local.anvil_tcp_port_ranges[count.index].min}-${local.anvil_tcp_port_ranges[count.index].max} for Anvil nodes"
}

# Anvil NSG Rules - UDP
resource "oci_core_network_security_group_security_rule" "anvil_ingress_udp" {
  count                     = var.anvil_count > 0 && var.anvil_security_group_id == "" ? length(local.anvil_udp_ports) : 0
  network_security_group_id = oci_core_network_security_group.anvil_data_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  udp_options {
    destination_port_range {
      min = local.anvil_udp_ports[count.index]
      max = local.anvil_udp_ports[count.index]
    }
  }

  description = "UDP port ${local.anvil_udp_ports[count.index]} for Anvil nodes"
}

# Anvil NSG Rules - Egress
resource "oci_core_network_security_group_security_rule" "anvil_egress" {
  count                     = var.anvil_count > 0 && var.anvil_security_group_id == "" ? 1 : 0
  network_security_group_id = oci_core_network_security_group.anvil_data_nsg[0].id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = var.sec_ip_cidr
  destination_type          = "CIDR_BLOCK"
  description               = "All outbound traffic for Anvil nodes"
}

# DSX Network Security Group
resource "oci_core_network_security_group" "dsx_nsg" {
  count          = var.dsx_count > 0 && var.dsx_security_group_id == "" ? 1 : 0
  compartment_id = var.common_config.compartment_id
  vcn_id         = var.common_config.vcn_id
  display_name   = "${local.resource_prefix_dsx}-nsg"

  defined_tags  = local.common_tags
  freeform_tags = { Purpose = "DSX-Data-Security" }
}

# DSX NSG Rules - ICMP
resource "oci_core_network_security_group_security_rule" "dsx_ingress_icmp" {
  count                     = var.dsx_count > 0 && var.dsx_security_group_id == "" ? 1 : 0
  network_security_group_id = oci_core_network_security_group.dsx_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"
  description               = "ICMP traffic for DSX nodes"
}

# DSX NSG Rules - TCP Single Ports
resource "oci_core_network_security_group_security_rule" "dsx_ingress_tcp" {
  count                     = var.dsx_count > 0 && var.dsx_security_group_id == "" ? length(local.dsx_tcp_ports) : 0
  network_security_group_id = oci_core_network_security_group.dsx_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = local.dsx_tcp_ports[count.index]
      max = local.dsx_tcp_ports[count.index]
    }
  }

  description = "TCP port ${local.dsx_tcp_ports[count.index]} for DSX nodes"
}

# DSX NSG Rules - TCP Port Ranges
resource "oci_core_network_security_group_security_rule" "dsx_ingress_tcp_ranges" {
  count                     = var.dsx_count > 0 && var.dsx_security_group_id == "" ? length(local.dsx_tcp_port_ranges) : 0
  network_security_group_id = oci_core_network_security_group.dsx_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = local.dsx_tcp_port_ranges[count.index].min
      max = local.dsx_tcp_port_ranges[count.index].max
    }
  }

  description = "TCP ports ${local.dsx_tcp_port_ranges[count.index].min}-${local.dsx_tcp_port_ranges[count.index].max} for DSX nodes"
}

# DSX NSG Rules - UDP
resource "oci_core_network_security_group_security_rule" "dsx_ingress_udp" {
  count                     = var.dsx_count > 0 && var.dsx_security_group_id == "" ? length(local.dsx_udp_ports) : 0
  network_security_group_id = oci_core_network_security_group.dsx_nsg[0].id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = var.sec_ip_cidr
  source_type               = "CIDR_BLOCK"

  udp_options {
    destination_port_range {
      min = local.dsx_udp_ports[count.index]
      max = local.dsx_udp_ports[count.index]
    }
  }

  description = "UDP port ${local.dsx_udp_ports[count.index]} for DSX nodes"
}

# DSX NSG Rules - Egress
resource "oci_core_network_security_group_security_rule" "dsx_egress" {
  count                     = var.dsx_count > 0 && var.dsx_security_group_id == "" ? 1 : 0
  network_security_group_id = oci_core_network_security_group.dsx_nsg[0].id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = var.sec_ip_cidr
  destination_type          = "CIDR_BLOCK"
  description               = "All outbound traffic for DSX nodes"
}

# --- Anvil Standalone Resources ---
resource "oci_core_instance" "anvil" {
  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Java Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Autonomous Linux"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Service Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Hub Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
  count               = var.anvil_count
  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = var.anvil_count > 1 ? "${var.deployment_name}-mds${count.index}" : "${var.deployment_name}-mds"
  shape               = var.anvil_shape

  # Handle Flex shapes
  dynamic "shape_config" {
    for_each = local.anvil_is_flex_shape ? [1] : []
    content {
      ocpus         = var.anvil_ocpus
      memory_in_gbs = var.anvil_memory_in_gbs
    }
  }

  # Source details (image)
  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = 200
  }

  # Network configuration
  create_vnic_details {
    subnet_id                 = var.common_config.subnet_id
    assign_public_ip          = var.common_config.assign_public_ip
    assign_ipv6ip             = "false"
    assign_private_dns_record = "true"
    nsg_ids                   = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
    display_name              = "${local.resource_prefix_anvil}-standalone-vnic"
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "false"
  # Commented out to avoid duplicate metadata volume - using separate oci_core_volume resource instead
  launch_volume_attachments {
    display_name = "${var.deployment_name}-mds-vol"
    is_read_only = "false"
    is_shareable = "false"
    launch_create_volume_details {
      compartment_id       = var.common_config.compartment_id
      display_name         = "${var.deployment_name}-mds-vol"
      size_in_gbs          = var.anvil_meta_disk_size
      volume_creation_type = "ATTRIBUTES"
      vpus_per_gb          = "10"
    }
    type = "paravirtualized"
  }

  # Metadata for cloud-init
  metadata = {
    ssh_authorized_keys = var.common_config.ssh_public_key
    "user_data" = var.anvil_count <= 1 ? base64encode(jsonencode({
      node = {
        ha_mode  = "Standalone"
        features = ["metadata"]
        hostname = "${var.deployment_name}-mds"
        networks = {
          (local.anvil_interface_name) = {
            roles = ["data", "mgmt"]
          }
        }
      }
      oci = {
        api_key     = file("${var.api_key}"),
        config_file = file("${var.config_file}")
      }
      cluster = {
        domainname  = "${var.domainname}"
        ntp_servers = ["169.254.169.254"]
        password    = "${var.admin_user_password}"
      }
      })) : base64encode(jsonencode({
      oci = {
        api_key     = file("${var.api_key}")
        config_file = file("${var.config_file}")
      }
      cluster = {
        domainname  = "${var.domainname}"
        ntp_servers = ["169.254.169.254"]
        password    = "${var.admin_user_password}"
      },
      node_index = "${tostring(count.index)}",
      nodes = {
        "0" = {
          features = ["metadata"],
          hostname = "${var.deployment_name}-mds0",
          ha_mode  = "Primary",
          networks = {
            (local.anvil_interface_name) = {
              roles = ["data", "mgmt", "ha"],
            }
          }
        },
        "1" = {
          features = ["metadata"],
          hostname = "${var.deployment_name}-mds1",
          ha_mode  = "Secondary",
          networks = {
            (local.anvil_interface_name) = {
              roles = ["data", "mgmt", "ha"],
            }
          }
        }
      }
    }))
  }

  # Fault domain - use per-instance fault domain if specified, otherwise fall back to common_config
  fault_domain = length(var.anvil_fault_domains) > 0 ? element(var.anvil_fault_domains, count.index % length(var.anvil_fault_domains)) : var.common_config.fault_domain

  # Capacity reservation
  capacity_reservation_id = var.anvil_capacity_reservation_id

  lifecycle {
    precondition {
      condition     = var.sa_anvil_destruction == true
      error_message = "The Anvil instance is protected. To destroy it, set 'sa_anvil_destruction = true'."
    }

    prevent_destroy = false

    # precondition {
    #   condition     = var.anvil_count == 0 || length(data.oci_core_shapes.anvil_shapes[0].shapes) > 0
    #   error_message = "The specified Anvil shape ${var.anvil_shape} is not available in the selected availability domain."
    # }
  }

  preserve_data_volumes_created_at_launch = false
  launch_options {
    boot_volume_type = "PARAVIRTUALIZED"
    network_type     = "PARAVIRTUALIZED"
    firmware         = "BIOS"
  }

  defined_tags  = local.common_tags
  freeform_tags = { Name = "${local.resource_prefix_anvil}-standalone", Type = "Anvil-Standalone" }

  depends_on = [oci_core_network_security_group.anvil_data_nsg]
}

# Anvil Metadata Volume
resource "oci_core_volume" "anvil_meta_vol" {
  count               = var.anvil_count
  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix_anvil}-standalone-meta-vol"
  size_in_gbs         = var.anvil_meta_disk_size

  # Performance configuration
  vpus_per_gb = var.anvil_meta_disk_iops != null ? ceil(var.anvil_meta_disk_iops / var.anvil_meta_disk_size) : 10

  defined_tags  = local.common_tags
  freeform_tags = { Name = "${local.resource_prefix_anvil}-standalone-meta-vol", Purpose = "Metadata" }
}

resource "oci_core_volume_attachment" "anvil_meta_vol_attach" {
  count           = var.anvil_count
  attachment_type = var.anvil_meta_disk_type
  instance_id     = oci_core_instance.anvil[count.index].id
  volume_id       = oci_core_volume.anvil_meta_vol[count.index].id
  display_name    = "${local.resource_prefix_anvil}-standalone-meta-attachment"
}

# --- DSX Data Services Node Resources ---
resource "oci_core_instance" "dsx" {
  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Java Management Service"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Oracle Autonomous Linux"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Service Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "OS Management Hub Agent"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Custom Logs Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Cloud Guard Workload Protection"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
  count               = var.dsx_count
  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${var.deployment_name}-dsx${count.index}"
  shape               = var.dsx_shape

  # Handle Flex shapes
  dynamic "shape_config" {
    for_each = local.dsx_is_flex_shape ? [1] : []
    content {
      ocpus         = var.dsx_ocpus
      memory_in_gbs = var.dsx_memory_in_gbs
    }
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "false"

  # Source details (image)
  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.dsx_block_volume_size
    boot_volume_vpus_per_gb = "10"
  }

  # Network configuration
  create_vnic_details {
    assign_ipv6ip             = "false"
    assign_private_dns_record = "true"
    subnet_id                 = var.common_config.subnet_id
    assign_public_ip          = var.common_config.assign_public_ip
    nsg_ids                   = local.effective_dsx_sg_id != null ? [local.effective_dsx_sg_id] : []
    display_name              = "${local.resource_prefix_dsx}${count.index + 1}-vnic"
  }

  # Metadata for cloud-init
  metadata = {
    ssh_authorized_keys = var.common_config.ssh_public_key
    "user_data" = base64encode(jsonencode({
      node = {
        features    = ["portal", "storage"]
        add_volumes = true
        hostname    = "${var.deployment_name}-dsx${count.index}"
        networks = {
          (local.dsx_interface_name) = {
            roles = ["data", "mgmt"]
          }
        }
      }
      oci = {
        api_key     = file("${var.api_key}"),
        config_file = file("${var.config_file}"),
      }
      cluster = {
        domainname  = "${var.domainname}"
        ntp_servers = ["169.254.169.254"]
        password    = "${var.admin_user_password}"
        metadata = {
          ips = var.anvil_count > 0 ? [var.anvil_count > 1 ? oci_core_private_ip.cluster_ip[0].ip_address : oci_core_instance.anvil[0].private_ip] : []
        }
      }
    }))
  }


  preserve_data_volumes_created_at_launch = false
  launch_options {
    boot_volume_type = "PARAVIRTUALIZED"
    network_type     = "PARAVIRTUALIZED"
    firmware         = "BIOS"
  }
  depends_on = [oci_core_instance.anvil, oci_core_private_ip.cluster_ip, oci_core_network_security_group.dsx_nsg]

  # Fault domain
  fault_domain = var.common_config.fault_domain

  # Capacity reservation
  capacity_reservation_id = var.dsx_capacity_reservation_id

  lifecycle {
    precondition {
      condition     = var.dsx_count == 0 || length(data.oci_core_shapes.dsx_shapes[0].shapes) > 0
      error_message = "The specified DSX shape ${var.dsx_shape} is not available in the selected availability domain."
    }
    prevent_destroy = false
  }

  defined_tags  = local.common_tags
  freeform_tags = { Name = "${local.resource_prefix_dsx}${count.index + 1}", Type = "DSX-Data-Services" }
}

# DSX Data Volumes
resource "oci_core_volume" "dsx_data_vols" {
  count = var.dsx_count * var.dsx_block_volume_count

  availability_domain = var.common_config.availability_domain
  compartment_id      = var.common_config.compartment_id
  display_name        = "${local.resource_prefix_dsx}${floor(count.index / var.dsx_block_volume_count) + 1}-data-vol${(count.index % var.dsx_block_volume_count) + 1}"
  size_in_gbs         = var.dsx_block_volume_size

  # Performance configuration
  vpus_per_gb = var.dsx_block_volume_iops != null ? ceil(var.dsx_block_volume_iops / var.dsx_block_volume_size) : 10

  defined_tags = local.common_tags
  freeform_tags = {
    Name             = "${local.resource_prefix_dsx}${floor(count.index / var.dsx_block_volume_count) + 1}-data-vol${(count.index % var.dsx_block_volume_count) + 1}"
    Purpose          = "DSX-Data-Storage"
    DSXInstanceIndex = floor(count.index / var.dsx_block_volume_count)
    VolumeIndex      = count.index % var.dsx_block_volume_count
  }
}

resource "oci_core_volume_attachment" "dsx_data_vols_attach" {
  count = var.dsx_count * var.dsx_block_volume_count

  attachment_type = var.dsx_block_volume_type
  instance_id     = oci_core_instance.dsx[floor(count.index / var.dsx_block_volume_count)].id
  volume_id       = oci_core_volume.dsx_data_vols[count.index].id
  display_name    = "${local.resource_prefix_dsx}${floor(count.index / var.dsx_block_volume_count) + 1}-data-attachment${(count.index % var.dsx_block_volume_count) + 1}"
}

data "oci_core_vnic_attachments" "anvil_vnic_attachments" {
  count          = var.anvil_count > 1 ? 1 : 0
  compartment_id = var.common_config.compartment_id
  instance_id    = oci_core_instance.anvil[1].id
}

resource "oci_core_private_ip" "cluster_ip" {
  count          = var.anvil_count > 1 ? 1 : 0
  vnic_id        = data.oci_core_vnic_attachments.anvil_vnic_attachments[0].vnic_attachments[0].vnic_id
  hostname_label = "${var.deployment_name}-cluster-ip"
  depends_on     = [oci_core_instance.anvil]
}

resource "oci_core_public_ip" "cluster_public_ip" {
  count          = var.anvil_count > 1 && var.common_config.assign_public_ip ? 1 : 0
  compartment_id = var.common_config.compartment_id
  lifetime       = "RESERVED"
  private_ip_id  = oci_core_private_ip.cluster_ip[0].id
  depends_on     = [oci_core_private_ip.cluster_ip]
}
