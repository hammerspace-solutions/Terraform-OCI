###########################################################################
# Oracle Cloud Infrastructure (OCI) Terraform Configuration - tfvars        #
##############################################################################

# --- Authentication and API ---
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaagksmgfomsiqdhwvu4njig5ndizoziancmmgksyfrs3s3udzvo6zq" # Your actual tenancy OCID
user_ocid        = "ocid1.user.oc1..aaaaaaaamb6q4dguaj22h5vdytxjam4jb5n7gw6s2x7s4yf4fnqx5dfgcn5a"    # Your actual user OCID
fingerprint      = "e6:f8:ec:5d:bd:af:fe:db:7d:a0:35:0c:ca:27:c6:15"                                 # Your actual API key fingerprint
private_key_path = "oci/oci_api_key.pem"                                                             # Path to your actual private key
region           = "us-sanjose-1"                                                                    # Target OCI region

admin_user_password = "Hammer.123!!"
domainname          = "localdomain"
api_key             = "oci/oci_api_key.pem"
config_file         = "oci/config"
# oci_cli_rc        = null  # Optional: OCI CLI RC file path

# --- Compartment, Network, and Availability Domain ---
compartment_ocid = "ocid1.tenancy.oc1..aaaaaaaagksmgfomsiqdhwvu4njig5ndizoziancmmgksyfrs3s3udzvo6zq"            # Your actual compartment OCID
vcn_id           = "ocid1.vcn.oc1.us-sanjose-1.amaaaaaaczb2xwaaa2kguwfidq4sirlxttcanjutsfquuuofmxticko6dzzq"    # Your actual VCN OCID
subnet_id        = "ocid1.subnet.oc1.us-sanjose-1.aaaaaaaaf7t5hsbzbghge57jel7zv3loqir6mvy56vkasxdxn7ocdwasgkmq" # Your actual subnet OCID
# nat_gateway_id = "ocid1.natgateway.oc1.us-sanjose-1.aaaaaaaakopzkjiqrqaq6xw3amr4odmq2lhz2d3ylpelu6zh4mtbcbtcz7sa"  # Required if assign_public_ip=false
# vcn_id            = "ocid1.vcn.oc1.us-sanjose-1.amaaaaaaczb2xwaaylogvqumeygfz3q3iouc2ukdd4reip7pvuuyjro6sc2a"
# subnet_id        = "ocid1.subnet.oc1.us-sanjose-1.aaaaaaaa3l62pwoif2qvc4muc7kvxyfbxst2qzwfnbn6ntxjezgusagcnpvq"
#subnet_id = "ocid1.subnet.oc1.us-sanjose-1.aaaaaaaamdiburqneon6egj34pfl5febfyp6zhvjzvaj37mj4zhh3ktg5nsa"
create_nat_gateway_for_existing_vcn = false
  create_networking = false  # Default
  vcn_cidr    = "10.0.0.0/16"  # Optional, has default
  subnet_cidr = "10.0.1.0/24"  # Optional, has default
ad_number        = 1                                                                                            # Availability Domain number (1, 2, or 3)

# --- Project Tagging & Meta ---
deployment_name = "bu-hs"
project_name    = "bu-hs" # Name prefix for all resources
tags            = {}          # Optional map of tags

# --- SSH Keys and Connectivity ---
ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC07v6lqSClHrUmP10bVCrTpEg3NUjjm5TEuievmpVaLKNjDKST0juDU0TaSrhLAf/5RTFvCYeL8dWxn6w4CcFBMzblHJ3EFR13+M+0dLeZWv+RV/1Ag/X/jNIJLQ9ozQYQyTqKJaVQJimV/BKuGRmsjYljUrTqIqFAFEy1CzeT6Of0Cb5YnK5BM9i00MbK6FNb+QMl0r+62uI/cJj5jQSnpvKCJtlix1yIH2itzf3KcuDazDe5XHsu4i78zNjhs6U8qb4b84uMF0wzJ/iPsBbyiSBQoJBVQf4PDqDU15UPxjZ/lipblq0igXoLYFv/XaqeQxfbafHGS6UCLMFqETZ4HBuCeYIx8MG5KDtQCEyK9kMSyG65VK8Fj7eWUWAISHP4bA0nRIez+40wIfoiTv4yoTRt49zRuQgIZ3CPnnl2NzuvMTo6pnp8spR+mLNfrp5sB46gE58AmsihXt6hrR/Al9ooK3xbsO0UAW5kYLQhURUH8XJCrBmB3ep7/NpYmEHvydFIzKBDQjvOG4PZKJtNkgYjO0Uw3R/M2SeNhkL+3l8iOZU1HqRfxmR8YT7XbiV6v1j+OVS9OnO8ABtq3/VLY4/uIJKQF0tJDKiei0+z7dL3hX/lJmKtMHuxAWzLR36HDII0i58jIDAazJ029i2WoQPEDjgmnFzKH4gfleT9iQ== " # Your actual SSH public key
ssh_keys_dir     = "ssh_keys"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              # Path to store SSH keys
assign_public_ip = true                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               # Assign public IPs to compute instances
fault_domain     = ""                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      # (Optional) Fault domain name for non-Anvil instances

# Anvil Fault Domains - for HA deployment across different fault domains
# Uncomment and configure to place Anvil instances in different fault domains
anvil_fault_domains = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2"]  # mds0 -> FD1, mds1 -> FD2

# --- Component Enablement ---
deploy_components = ["hammerspace"] #, "storage", "ecgroup", "ansible"] # Define the required components "all", "ecgroup", "ansible", "bastion", "clients", "storage", "ecgroup" or "hammerspace"

# --- Hammerspace Configuration ---
hammerspace_sa_anvil_destruction = true  # Allow destruction of standalone Anvil (required for terraform operations)

# Tell Terraform to use existing Anvil instances
hammerspace_use_existing_anvil = false

# Provide the IP addresses of your existing Anvil instances
hammerspace_existing_anvil_ips = ["10.0.1.127", "10.0.1.55"]  # Replace with your actual Anvil IPs
    
# Provide the admin password for the existing Anvil instances
hammerspace_existing_anvil_password = "Hammer.123!!"  # Replace with actual password

# Tell Terraform to use existing DSX instances
hammerspace_use_existing_dsx = false

# Provide the IP addresses of your existing DSX instances
hammerspace_existing_dsx_ips = ["10.0.1.192", "10.0.1.102"]  # Replace with your actual DSX IPs

# Since we're using existing infrastructure, set the deployment counts to 0
hammerspace_anvil_count = 1
hammerspace_dsx_count = 1


##############################################################################
# Images & Shapes - Replace with actual valid OCIDs from your region        #
##############################################################################

# --- Compute Image OCIDs (REPLACE THESE WITH REAL VALUES) ---
# Use the script above or OCI Console to get valid image OCIDs
clients_instance_count          = 0
clients_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
clients_instance_shape          = "VM.Standard.E4.Flex"
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


storage_instance_count          = 1
storage_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
storage_instance_shape          = "VM.Standard.E4.Flex"
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
add_storage_server_volumes = true
volume_group_name        = "vg-auto"
share_name               = "test"


# hammerspace_image_id = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa3pbtf4hgs3cjvg4nrkwxuyxupsq5cwz3j5u7y66rlllx4wjmqxha" # Oracle Linux 8


hammerspace_anvil_image_id = "ocid1.image.oc1.us-sanjose-1.aaaaaaaabsug23irt6rmjh7ibdwugcvvmbotbvnasuyuhz77gxm35exef2ka"  # Leave empty to use hammerspace_image_id "ocid1.image.oc1.us-sanjose-1.aaaaaaaaa4bozgzscm7kdw6oqah6klihgujnucdj3p4sfdgs3um6sqckrp4q" #
hammerspace_anvil_instance_shape       = "VM.Standard.E4.Flex"
hammerspace_anvil_ocpus                = 4
hammerspace_anvil_memory_gbs           = 32
hammerspace_anvil_security_group_id    = ""
hammerspace_anvil_meta_disk_size       = 200  # Smaller for testing
hammerspace_anvil_meta_disk_type       = "paravirtualized"
hammerspace_anvil_meta_disk_iops       = null
hammerspace_anvil_meta_disk_throughput = null
hammerspace_anvil_enable_sriov         = false  # Disabled - Hammerspace images use PARAVIRTUALIZED


hammerspace_dsx_image_id   = "ocid1.image.oc1.us-sanjose-1.aaaaaaaabsug23irt6rmjh7ibdwugcvvmbotbvnasuyuhz77gxm35exef2ka"  # Leave empty to use hammerspace_image_id
hammerspace_dsx_instance_shape          = "VM.Standard.E4.Flex"
hammerspace_dsx_ocpus                   = 4
hammerspace_dsx_memory_gbs              = 32
hammerspace_dsx_security_group_id       = ""
hammerspace_dsx_block_volume_size       = 200 # Smaller for testing
hammerspace_dsx_block_volume_type       = "paravirtualized"
hammerspace_dsx_block_volume_iops       = null
hammerspace_dsx_block_volume_throughput = null
hammerspace_dsx_enable_sriov            = false  # Disabled - Hammerspace images use PARAVIRTUALIZED
hammerspace_dsx_block_volume_count      = 1
hammerspace_dsx_add_vols                = true

# ecgroup_node_count                 = 4
# ecgroup_image_id                = "ocid1.image.oc1.us-sanjose-1.aaaaaaaapah7sttqniy7ppbladubs7g6cecnf2m3abkq2av777qvivlqhd2a" # Debian ssh -i ssh_keys/ansible_admin_key debian@192.9.231.97   
# ecgroup_instance_shape             = "VM.Standard.E2.8"
# ecgroup_ocpus                      = 4
# ecgroup_memory_gbs                 = 32
# ecgroup_boot_volume_size           = 200
# ecgroup_boot_volume_type           = "paravirtualized"
# ecgroup_metadata_volume_type       = "paravirtualized"
# ecgroup_metadata_volume_size       = 200
# ecgroup_metadata_volume_throughput = null
# ecgroup_metadata_volume_iops       = null
# ecgroup_storage_volume_count       = 8
# ecgroup_storage_volume_type        = "paravirtualized"
# ecgroup_storage_volume_size        = 200
# ecgroup_storage_volume_throughput  = null
# ecgroup_storage_volume_iops        = null
# ecgroup_user_data                  = "./templates/ecgroup_node.sh"
ecgroup_add_to_hammerspace = true
ecgroup_volume_group_name  = "ecg-vg-auto"
ecgroup_share_name         = "ecg-share"
add_ecgroup_volumes = true

# ============================================================================
# UNIFIED DEVICE-AGNOSTIC ECGROUP CONFIGURATION
# ============================================================================
# This configuration automatically adapts to the chosen instance shape:
# - DenseIO shapes (e.g., VM.DenseIO.E5.Flex, BM.DenseIO.E5.128): Uses local NVMe drives
# - Standard shapes (e.g., VM.Standard.E2.8): Uses OCI block storage volumes
#
# The RozoFS layout is auto-calculated based on total available devices:
#   - Layout 0 (2+1): 3-5 devices  -> 1 drive fault tolerance
#   - Layout 1 (4+2): 6-11 devices -> 2 drive fault tolerance
#   - Layout 2 (8+4): 12+ devices  -> 4 drive fault tolerance
# ============================================================================

ecgroup_node_count     = 4
ecgroup_image_id       = "ocid1.image.oc1.us-sanjose-1.aaaaaaaaus2yuzfbaogsfrkpe7pzkvbnjwzkm3ivn5cs2hwuv2dlxuhgbriq"  # Rocky 9.6

# === SHAPE SELECTION (Change this to switch between NVMe and block storage) ===
# Option 1: High-performance with local NVMe (DenseIO shapes)
ecgroup_instance_shape = "VM.DenseIO.E5.Flex"
ecgroup_ocpus          = 16      # 24 OCPUs = 3 × 6.8TB NVMe drives per node
ecgroup_memory_gbs     = 192     # 12 GB RAM per OCPU (required for DenseIO.E5.Flex)

# Option 2: Standard shape with block storage (uncomment to use)
# ecgroup_instance_shape = "VM.Standard.E2.8"
# ecgroup_ocpus          = 4
# ecgroup_memory_gbs     = 32

# === BOOT AND METADATA VOLUMES (same for all shapes) ===
ecgroup_boot_volume_size           = 200
ecgroup_boot_volume_type           = "paravirtualized"
ecgroup_metadata_volume_type       = "paravirtualized"
ecgroup_metadata_volume_size       = 200
ecgroup_metadata_volume_throughput = null
ecgroup_metadata_volume_iops       = null

# === STORAGE CONFIGURATION (device-agnostic) ===
# For DenseIO shapes: Set ecgroup_storage_volume_count = 0 (uses local NVMe)
# For Standard shapes: Set ecgroup_storage_volume_count = 8 (creates 8 block volumes per node)
ecgroup_storage_volume_count       = 0    # 0 = use local NVMe, >0 = create block volumes
ecgroup_storage_volume_type        = "paravirtualized"
ecgroup_storage_volume_size        = 200  # Size in GB (only used if volume_count > 0)
ecgroup_storage_volume_throughput  = null
ecgroup_storage_volume_iops        = null

# === UNIFIED USER-DATA SCRIPT (works with both NVMe and block storage) ===
ecgroup_user_data                  = "./templates/ecgroup_node_unified.sh"

# === DEPLOYMENT NOTES ===
# Current configuration (VM.DenseIO.E5.Flex with 24 OCPUs):
#   - Expected: 3 NVMe drives per node × 4 nodes = 12 drives
#   - Auto-detected layout: Layout 2 (8+4) if 12 drives, or Layout 1 (4+2) if 6-11 drives
#   - Usable capacity: ~67% of raw capacity (after erasure coding overhead)
#
# To switch to block storage:
#   1. Change ecgroup_instance_shape to "VM.Standard.E2.8"
#   2. Set ecgroup_storage_volume_count = 8
#   3. Adjust ecgroup_ocpus and ecgroup_memory_gbs as needed
#   4. Deploy - the system will auto-detect block storage and configure accordingly

ansible_instance_count   = 1
ansible_image_id         = "ocid1.image.oc1.us-sanjose-1.aaaaaaaa7dmcq6eafehtb4an3xiseqyshfcgdnrjuy3rqhbmcqayef255qha" # Ubuntu 24.04
ansible_instance_shape   = "VM.Standard.E5.Flex"
ansible_ocpus            = 2
ansible_memory_gbs       = 16
ansible_boot_volume_size = 200
ansible_boot_volume_type = "paravirtualized"
ansible_user_data        = "./templates/ansible_config_ubuntu.sh"
ansible_target_user      = "ubuntu"


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
