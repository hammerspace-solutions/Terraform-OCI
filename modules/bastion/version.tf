terraform {
  required_version = ">= 0.12.0"

  required_providers {
    oci = {
      source  = "hashicorp/oci"
      version = "6.21.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}