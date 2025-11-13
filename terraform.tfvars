###########################################################################
# Oracle Cloud Infrastructure (OCI) Terraform Configuration - tfvars        #
##############################################################################

# --- Authentication and API ---
tenancy_ocid     = "ocid1.tenancy.oc1.." # Your actual tenancy OCID
user_ocid        = "ocid1.user.oc1.."    # Your actual user OCID
fingerprint      = "e6:f8:ec:5d:b"                                 # Your actual API key fingerprint
private_key_path = "oci/oci_api_key.pem"                                                             # Path to your actual private key
region           = "us-sanjose-1"                                                                    # Target OCI region

admin_user_password = "PASSWORD"
domainname          = "localdomain"
api_key             = "oci/oci_api_key.pem"
config_file         = "oci/config"

# --- Compartment, Network, and Availability Domain ---
compartment_ocid = "ocid1.tenancy.oc1.."            # Your actual compartment OCID
vcn_id           = "ocid1.vcn.oc1.us-sanjose-1."
subnet_id        = "ocid1.subnet.oc1.us-sanjose-1"
create_nat_gateway_for_existing_vcn = false
  create_networking = false  # Default
  vcn_cidr    = "10.0.0.0/16"  # Optional, has default
  subnet_cidr = "10.0.1.0/24"  # Optional, has default
ad_number        = 1           # Availability Domain number (1, 2, or 3)

# --- Project Tagging & Meta ---
deployment_name = "bu-hs"
project_name    = "bu-hs" # Name prefix for all resources
tags            = {}          # Optional map of tags

# --- SSH Keys and Connectivity ---
ssh_public_key   = "PUBLIC_KEY" # Your actual SSH public key
ssh_keys_dir     = "ssh_keys"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              # Path to store SSH keys
assign_public_ip = true                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                # Assign public IPs to compute instances
fault_domain     = ""                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      # (Optional) Fault domain name
# --- Component Enablement ---
deploy_components = ["hammerspace", "storage", "ansible"] # Define the required components "all", "ansible", "bastion", "clients", "storage", "ecgroup" or "hammerspace"

# --- Hammerspace Configuration ---
hammerspace_sa_anvil_destruction = true  # Allow destruction of standalone Anvil (required for terraform operations)

# Tell Terraform to use existing Anvil instances
hammerspace_use_existing_anvil = true

# Provide the IP addresses of your existing Anvil instances
hammerspace_existing_anvil_ips = ["10.0.1.x", "10.0.1.y"]  # Replace with your actual Anvil IPs
    
# Provide the admin password for the existing Anvil instances
hammerspace_existing_anvil_password = "PASSWORD"  # Replace with actual password

# Tell Terraform to use existing DSX instances
hammerspace_use_existing_dsx = true

# Provide the IP addresses of your existing DSX instances
hammerspace_existing_dsx_ips = ["10.0.1.a", "10.0.1.b"]  # Replace with your actual DSX IPs

# Since we're using existing infrastructure, set the deployment counts to 0
hammerspace_anvil_count = 0
hammerspace_dsx_count = 0


##############################################################################
# Images & Shapes - Replace with actual valid OCIDs from your region        #
##############################################################################

# --- Compute Image OCIDs (REPLACE THESE WITH REAL VALUES) ---
# Use the script above or OCI Console to get valid image OCIDs
clients_instance_count          = 0
clients_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
clients_instance_shape          = "VM.Standard.E5.Flex"
clients_ocpus                   = 2
clients_memory_gbs              = 16
clients_boot_volume_size        = 50
clients_boot_volume_type        = "paravirtualized"
clients_block_volume_count      = 1
clients_block_volume_size       = 50
clients_block_volume_type       = "paravirtualized"
clients_block_volume_throughput = null
clients_block_volume_iops       = null
clients_user_data               = "./templates/client_config.sh"
clients_target_user             = "ubuntu"


storage_instance_count          = 2
storage_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
storage_instance_shape          = "VM.Standard.E5.Flex"
storage_ocpus                   = 2
storage_memory_gbs              = 16
storage_boot_volume_size        = 50
storage_boot_volume_type        = "paravirtualized"
storage_block_volume_count      = 2
storage_raid_level              = "raid-0"
storage_block_volume_size       = 50
storage_block_volume_type       = "paravirtualized"
storage_block_volume_throughput = null
storage_block_volume_iops       = null
storage_user_data               = "./templates/storage_server.sh"
storage_target_user             = "ubuntu"

hammerspace_image_id = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa3pbtf4hgs3cjvg4nrkwxuyxupsq5cwz3j5u7y66rlllx4wjmqxha" # Oracle Linux 8


hammerspace_anvil_instance_shape       = "VM.Standard.E2.8"
hammerspace_anvil_ocpus                = 4
hammerspace_anvil_memory_gbs           = 32
hammerspace_anvil_security_group_id    = ""
hammerspace_anvil_meta_disk_size       = 200  # Smaller for testing
hammerspace_anvil_meta_disk_type       = "paravirtualized"
hammerspace_anvil_meta_disk_iops       = null
hammerspace_anvil_meta_disk_throughput = null


hammerspace_dsx_instance_shape          = "VM.Standard.E2.8"
hammerspace_dsx_ocpus                   = 2
hammerspace_dsx_memory_gbs              = 16
hammerspace_dsx_security_group_id       = ""
hammerspace_dsx_block_volume_size       = 200 # Smaller for testing
hammerspace_dsx_block_volume_type       = "paravirtualized"
hammerspace_dsx_block_volume_iops       = null
hammerspace_dsx_block_volume_throughput = null
hammerspace_dsx_block_volume_count      = 1
hammerspace_dsx_add_vols                = true

ecgroup_node_count                 = 4
ecgroup_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaapah7sttqniy7ppbladubs7g6cecnf2m3abkq2av777qvivlqhd2a" # Ubuntu 24.04
ecgroup_instance_shape             = "VM.Standard.E5.Flex"
ecgroup_ocpus                      = 4
ecgroup_memory_gbs                 = 32
ecgroup_boot_volume_size           = 200
ecgroup_boot_volume_type           = "paravirtualized"
ecgroup_metadata_volume_type       = "paravirtualized"
ecgroup_metadata_volume_size       = 200
ecgroup_metadata_volume_throughput = null
ecgroup_metadata_volume_iops       = null
ecgroup_storage_volume_count       = 8
ecgroup_storage_volume_type        = "paravirtualized"
ecgroup_storage_volume_size        = 200
ecgroup_storage_volume_throughput  = null
ecgroup_storage_volume_iops        = null
ecgroup_user_data                  = "./templates/ecgroup_node.sh"

ansible_instance_count   = 1
ansible_image_id         = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
ansible_instance_shape   = "VM.Standard.E5.Flex"
ansible_ocpus            = 2
ansible_memory_gbs       = 16
ansible_boot_volume_size = 200
ansible_boot_volume_type = "paravirtualized"
ansible_user_data        = "./templates/ansible_config_ubuntu.sh"
ansible_target_user      = "ubuntu"
volume_group_name        = "vg-auto"
share_name               = "test"

# Bastion specific variables (bastion_ prefix)
#
# The Bastion is a specific type of client. It has no configuration and exists
# solely so that a user can login with a public IP address and access their
# clients and storage instances.

bastion_instance_count   = 0
bastion_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
bastion_instance_shape   = "VM.Standard.E5.Flex"
bastion_ocpus            = 2
bastion_memory_gbs       = 16
bastion_boot_volume_size = 200
bastion_boot_volume_type = "paravirtualized"
bastion_user_data        = "./templates/ansible_config_ubuntu.sh"
bastion_target_user      = "ubuntu"
