# Networking Module Outputs

output "vcn_id" {
  description = "OCID of the created VCN"
  value       = oci_core_vcn.this.id
}

output "subnet_id" {
  description = "OCID of the created subnet"
  value       = oci_core_subnet.this.id
}

output "nat_gateway_id" {
  description = "OCID of the NAT gateway (if created)"
  value       = var.create_nat_gateway ? oci_core_nat_gateway.this[0].id : null
}

output "internet_gateway_id" {
  description = "OCID of the internet gateway (if created)"
  value       = var.create_internet_gateway ? oci_core_internet_gateway.this[0].id : null
}

output "route_table_id" {
  description = "OCID of the route table"
  value       = oci_core_route_table.this.id
}

output "security_list_id" {
  description = "OCID of the security list"
  value       = oci_core_security_list.this.id
}

output "vcn_cidr" {
  description = "CIDR block of the VCN"
  value       = var.vcn_cidr
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = var.subnet_cidr
}