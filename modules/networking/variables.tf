# Networking Module Variables

variable "compartment_id" {
  description = "The OCID of the compartment where networking resources will be created"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "create_nat_gateway" {
  description = "Whether to create a NAT gateway"
  type        = bool
  default     = false
}

variable "create_internet_gateway" {
  description = "Whether to create an internet gateway"
  type        = bool
  default     = false
}

variable "availability_domain" {
  description = "Availability domain for regional subnets"
  type        = string
}