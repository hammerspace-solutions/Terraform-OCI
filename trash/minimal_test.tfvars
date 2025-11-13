##############################################################################
# Minimal OCI Terraform Configuration for Testing                            #
##############################################################################

# --- Authentication and API ---
tenancy_ocid     = "your-actual-tenancy-ocid"
user_ocid        = "your-actual-user-ocid"
fingerprint      = "your-actual-fingerprint"
private_key_path = "/path/to/your/private/key.pem"
region           = "uk-london-1"

# --- Compartment, Network, and Availability Domain ---
compartment_ocid = "your-actual-compartment-ocid"
vcn_id           = "your-actual-vcn-ocid"
subnet_id        = "your-actual-subnet-ocid"
ad_number        = 1

# --- Project Settings ---
project_name     = "hstest"
tags             = {}
ssh_public_key   = "your-actual-ssh-public-key"
ssh_keys_dir     = "./ssh"
assign_public_ip = true
fault_domain     = ""

# --- Component Enablement (Only Hammerspace for testing) ---
deploy_components = ["hammerspace"]

# --- Images (Replace with actual valid Oracle Linux 8 OCIDs) ---
clients_image_id     = "ocid1.image.oc1.uk-london-1.your-actual-image-ocid"
storage_image_id     = "ocid1.image.oc1.uk-london-1.your-actual-image-ocid"
hammerspace_image_id = "ocid1.image.oc1.uk-london-1.your-actual-image-ocid"
ansible_image_id     = "ocid1.image.oc1.uk-london-1.your-actual-image-ocid"
ecgroup_image_id     = "ocid1.image.oc1.uk-london-1.your-actual-image-ocid"

# --- Shapes ---
clients_instance_shape           = "VM.Standard.E4.Flex"
storage_instance_shape           = "VM.Standard.E4.Flex"
hammerspace_anvil_instance_shape = "VM.Standard.E4.Flex"
hammerspace_dsx_instance_shape   = "VM.Standard.E4.Flex"
ecgroup_instance_shape           = "VM.Standard.E4.Flex"
ansible_instance_shape           = "VM.Standard.E4.Flex"

# --- Small Resources for Testing ---
clients_ocpus                = 1
clients_memory_gbs           = 8
storage_ocpus                = 1
storage_memory_gbs           = 8
hammerspace_anvil_ocpus      = 2
hammerspace_anvil_memory_gbs = 16
hammerspace_dsx_ocpus        = 1
hammerspace_dsx_memory_gbs   = 8
ecgroup_ocpus                = 2
ecgroup_memory_gbs           = 16
ansible_ocpus                = 1
ansible_memory_gbs           = 8

# --- Instance Counts (Minimal for testing) ---
clients_instance_count  = 0
storage_instance_count  = 0
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 1
ecgroup_node_count      = 0
ansible_instance_count  = 0

# --- Hammerspace Settings ---
hammerspace_profile_id                  = ""
hammerspace_anvil_security_group_id     = ""
hammerspace_dsx_security_group_id       = ""
hammerspace_sa_anvil_destruction        = true
hammerspace_anvil_meta_disk_size        = 50
hammerspace_anvil_meta_disk_type        = "paravirtualized"
hammerspace_anvil_meta_disk_iops        = null
hammerspace_anvil_meta_disk_throughput  = null
hammerspace_dsx_block_volume_size       = 50
hammerspace_dsx_block_volume_type       = "paravirtualized"
hammerspace_dsx_block_volume_iops       = null
hammerspace_dsx_block_volume_throughput = null
hammerspace_dsx_block_volume_count      = 1
hammerspace_dsx_add_vols                = true

# --- Volume Settings ---
clients_boot_volume_size        = 50
clients_boot_volume_type        = "paravirtualized"
clients_block_volume_count      = 1
clients_block_volume_size       = 50
clients_block_volume_type       = "paravirtualized"
clients_block_volume_throughput = null
clients_block_volume_iops       = null

storage_boot_volume_size        = 50
storage_boot_volume_type        = "paravirtualized"
storage_block_volume_count      = 2
storage_raid_level              = "raid-0"
storage_block_volume_size       = 50
storage_block_volume_type       = "paravirtualized"
storage_block_volume_throughput = null
storage_block_volume_iops       = null

ecgroup_boot_volume_size           = 50
ecgroup_boot_volume_type           = "paravirtualized"
ecgroup_metadata_volume_type       = "paravirtualized"
ecgroup_metadata_volume_size       = 50
ecgroup_metadata_volume_throughput = null
ecgroup_metadata_volume_iops       = null
ecgroup_storage_volume_count       = 0
ecgroup_storage_volume_type        = "paravirtualized"
ecgroup_storage_volume_size        = 0
ecgroup_storage_volume_throughput  = null
ecgroup_storage_volume_iops        = null

ansible_boot_volume_size = 50
ansible_boot_volume_type = "paravirtualized"

# --- User Settings ---
clients_user_data   = ""
clients_target_user = "opc"
storage_user_data   = ""
storage_target_user = "opc"
ecgroup_user_data   = ""
ansible_user_data   = ""
ansible_target_user = "opc"
volume_group_name   = "vg-auto"
share_name          = ""
