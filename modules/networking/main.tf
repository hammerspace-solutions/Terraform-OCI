# Networking Module - Creates VCN, Subnet, and Gateways

locals {
  vcn_name    = "${var.project_name}-vcn"
  subnet_name = "${var.project_name}-subnet"
}

# Create VCN
resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = local.vcn_name
  dns_label      = replace(lower(var.project_name), "/[^a-z0-9]/", "")
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = local.vcn_name
    Type = "VCN"
  }
}

# Create Internet Gateway (if needed)
resource "oci_core_internet_gateway" "this" {
  count          = var.create_internet_gateway ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = "${var.project_name}-igw"
    Type = "Internet-Gateway"
  }
}

# Create NAT Gateway (if needed)
resource "oci_core_nat_gateway" "this" {
  count          = var.create_nat_gateway ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-nat-gateway"
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = "${var.project_name}-nat-gateway"
    Type = "NAT-Gateway"
  }
}

# Create Route Table
resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-route-table"

  # Add Internet Gateway route if IGW is created AND NAT is not created
  dynamic "route_rules" {
    for_each = var.create_internet_gateway && !var.create_nat_gateway ? [1] : []
    content {
      network_entity_id = oci_core_internet_gateway.this[0].id
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
    }
  }

  # Add NAT Gateway route if NAT is created (takes precedence over IGW)
  dynamic "route_rules" {
    for_each = var.create_nat_gateway ? [1] : []
    content {
      network_entity_id = oci_core_nat_gateway.this[0].id
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
    }
  }
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = "${var.project_name}-route-table"
    Type = "Route-Table"
  }
}

# Create Security List
resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-security-list"

  # Egress rule - Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # Ingress rule - SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress rule - ICMP
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = var.vcn_cidr
    
    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress rule - Allow all from within VCN
  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = "${var.project_name}-security-list"
    Type = "Security-List"
  }
}

# Create Subnet
resource "oci_core_subnet" "this" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = local.subnet_name
  dns_label                  = "subnet"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.this.id
  security_list_ids          = [oci_core_security_list.this.id]
  
  defined_tags  = var.tags
  freeform_tags = {
    Name = local.subnet_name
    Type = "Subnet"
  }
}