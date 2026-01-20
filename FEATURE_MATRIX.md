# Terraform-OCI-SplitFD Feature Matrix

This document provides a comprehensive overview of all features and capabilities supported by this Terraform configuration.

---

## Component Deployment

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Deploy Hammerspace Anvil (new) | ✅ Yes | `hammerspace_anvil_count = 1` | Deploy new standalone Anvil |
| Deploy Hammerspace Anvil HA | ✅ Yes | `hammerspace_anvil_count = 2` | Deploy 2 Anvils in HA mode |
| Use Existing Anvil | ✅ Yes | `hammerspace_use_existing_anvil = true` | Connect to pre-existing Anvil |
| Deploy DSX Nodes | ✅ Yes | `hammerspace_dsx_count = N` | Deploy N DSX data service nodes |
| Use Existing DSX | ✅ Yes | `hammerspace_use_existing_dsx = true` | Use pre-existing DSX nodes |
| Deploy ECGroup (RozoFS) | ✅ Yes | `deploy_components = ["ecgroup"]` | Erasure-coded storage cluster |
| Deploy Storage Servers | ✅ Yes | `deploy_components = ["storage"]` | Generic storage server nodes |
| Deploy Client Instances | ✅ Yes | `deploy_components = ["clients"]` | NFS/SMB client instances |
| Deploy Ansible Controller | ✅ Yes | `deploy_components = ["ansible"]` | Automation controller node |
| Deploy Bastion Host | ✅ Yes | `deploy_components = ["bastion"]` | SSH jump host |
| Deploy All Components | ✅ Yes | `deploy_components = ["all"]` | Deploy everything |

---

## Networking

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Create New VCN | ✅ Yes | `create_networking = true` | Auto-create VCN |
| Use Existing VCN | ✅ Yes | `vcn_id = "ocid..."` | Use pre-existing VCN |
| Use Existing Subnet | ✅ Yes | `subnet_id = "ocid..."` | Use pre-existing subnet |
| Custom VCN CIDR | ✅ Yes | `vcn_cidr = "10.0.0.0/16"` | Define VCN address space |
| Custom Subnet CIDR | ✅ Yes | `subnet_cidr = "10.0.1.0/24"` | Define subnet address space |
| Public IP Assignment | ✅ Yes | `assign_public_ip = true/false` | Assign public IPs |
| NAT Gateway (existing VCN) | ✅ Yes | `nat_gateway_id` or `create_nat_gateway_for_existing_vcn` | NAT for private instances |
| SR-IOV (VFIO) Networking | ✅ Yes | `hammerspace_anvil_enable_sriov` | High-performance networking |
| Custom Security Groups | ✅ Yes | `hammerspace_anvil_security_group_id` | Use existing NSGs |

---

## Availability & Placement

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Availability Domain Selection | ✅ Yes | `ad_number = 1/2/3` | Choose AD |
| Fault Domain Selection | ✅ Yes | `fault_domain = "FAULT-DOMAIN-N"` | Place in specific FD |
| Anvil Fault Domain Distribution | ✅ Yes | `anvil_fault_domains = ["FD-1", "FD-2"]` | HA across fault domains |
| Capacity Reservations | ✅ Yes | `hammerspace_anvil_capacity_reservation_id` | Reserved capacity |

---

## Instance Configuration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Flex Shape Support | ✅ Yes | `*_instance_shape = "VM.Standard.E4.Flex"` | Configurable OCPUs/memory |
| Bare Metal Shapes | ✅ Yes | `*_instance_shape = "BM.DenseIO.E5.128"` | High-performance BM |
| Custom OCPUs | ✅ Yes | `hammerspace_anvil_ocpus = N` | CPU allocation |
| Custom Memory | ✅ Yes | `hammerspace_anvil_memory_gbs = N` | Memory allocation |
| Custom Image IDs | ✅ Yes | `hammerspace_image_id`, `hammerspace_anvil_image_id`, `hammerspace_dsx_image_id` | Specific images |

---

## Storage Configuration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Anvil Metadata Disk Size | ✅ Yes | `hammerspace_anvil_meta_disk_size` | Metadata volume size |
| DSX Block Volumes | ✅ Yes | `hammerspace_dsx_block_volume_count/size` | Data volumes per DSX |
| Custom IOPS | ✅ Yes | `*_volume_iops` | Performance tuning |
| Custom Throughput | ✅ Yes | `*_volume_throughput` | Performance tuning |
| iSCSI vs Paravirtualized | ✅ Yes | `*_volume_type` | Attachment type |
| RAID Configuration | ✅ Yes | `storage_raid_level = "raid-0/5/6"` | Storage server RAID |

---

## Volume Groups & Shares (Hammerspace)

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| **DSX Volume Group** | ✅ Yes | `hammerspace_dsx_add_vols = true` | Auto-add DSX volumes to Anvil |
| **Storage Server Volume Group** | ✅ Yes | `volume_group_name = "vg-auto"` | Group storage server volumes |
| **Storage Server Share** | ✅ Yes | `share_name = "myshare"` | NFS/SMB share on storage VG |
| **ECGroup Volume Group** | ✅ Yes | `ecgroup_volume_group_name = "ecg-vg"` | Group ECGroup volumes |
| **ECGroup Share** | ✅ Yes | `ecgroup_share_name = "ecg-share"` | NFS/SMB share on ECGroup VG |
| Auto-add Storage Volumes | ✅ Yes | `add_storage_server_volumes = true` | Register storage volumes in HS |
| Auto-add ECGroup Volumes | ✅ Yes | `add_ecgroup_volumes = true` | Register ECGroup volumes in HS |
| ECGroup to Hammerspace Integration | ✅ Yes | `ecgroup_add_to_hammerspace = true` | Add ECGroup as storage node |

### Volume Group Workflow

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              Hammerspace Anvil                                │
│                           (Metadata Controller)                               │
└───────────────────────────────────────────────────────────────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│     DSX Nodes       │   │   Storage Servers   │   │      ECGroup        │
│  (Hammerspace Data  │   │  (Generic Storage)  │   │   (RozoFS Cluster)  │
│     Services)       │   │                     │   │                     │
│                     │   │                     │   │                     │
│  ┌───────────────┐  │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│  │ Block Volumes │  │   │  │ Block Volumes │  │   │  │ RozoFS Volume │  │
│  │ (auto-added)  │  │   │  │               │  │   │  │               │  │
│  └───────────────┘  │   │  └───────────────┘  │   │  └───────────────┘  │
│         │           │   │         │           │   │         │           │
│         ▼           │   │         ▼           │   │         ▼           │
│  ┌───────────────┐  │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│  │ (Managed by   │  │   │  │ Volume Group  │  │   │  │ Volume Group  │  │
│  │  Anvil auto)  │  │   │  │  "vg-auto"    │  │   │  │ "ecg-vg-auto" │  │
│  └───────────────┘  │   │  └───────────────┘  │   │  └───────────────┘  │
│                     │   │         │           │   │         │           │
│                     │   │         ▼           │   │         ▼           │
│                     │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│                     │   │  │    Share      │  │   │  │    Share      │  │
│                     │   │  │   "myshare"   │  │   │  │  "ecg-share"  │  │
│                     │   │  └───────────────┘  │   │  └───────────────┘  │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘

Component          │ Module              │ Volume Group Variable      │ Share Variable
───────────────────┼─────────────────────┼────────────────────────────┼──────────────────
DSX Nodes          │ hammerspace         │ (auto-managed by Anvil)    │ (via Anvil UI)
Storage Servers    │ storage_servers     │ volume_group_name          │ share_name
ECGroup (RozoFS)   │ ecgroup             │ ecgroup_volume_group_name  │ ecgroup_share_name
```

### Example Configuration

```hcl
# DSX - Volumes auto-added to Anvil
hammerspace_dsx_count = 2
hammerspace_dsx_add_vols = true           # Auto-add DSX volumes to Anvil

# Storage Servers - Separate volume group & share
volume_group_name          = "storage-vg"   # Volume group for storage servers
share_name                 = "storage-data" # NFS/SMB share name
add_storage_server_volumes = true           # Auto-register in Hammerspace

# ECGroup - Separate volume group & share (if using ECGroup)
ecgroup_add_to_hammerspace = true           # Enable ECGroup integration
ecgroup_volume_group_name  = "ecg-vg"       # ECGroup volume group name
ecgroup_share_name         = "ecg-data"     # ECGroup share name
add_ecgroup_volumes        = true           # Auto-register ECGroup volumes
```

---

## ECGroup (RozoFS) Features

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| ECGroup Node Deployment | ✅ Yes | `ecgroup_node_count = N` | Number of RozoFS nodes |
| Metadata Volumes | ✅ Yes | `ecgroup_metadata_volume_size` | DRBD metadata storage |
| Storage Volumes | ✅ Yes | `ecgroup_storage_volume_count/size` | Data storage volumes |
| Add to Hammerspace | ✅ Yes | `ecgroup_add_to_hammerspace = true` | Register as storage node |
| ECGroup Volume Groups | ✅ Yes | `ecgroup_volume_group_name` | Volume group in HS |
| ECGroup Shares | ✅ Yes | `ecgroup_share_name` | NFS share creation |

---

## Automation & Integration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Ansible Auto-Configuration | ✅ Yes | `deploy_components = ["ansible"]` | Automated setup |
| Add Storage Volumes to HS | ✅ Yes | `add_storage_server_volumes = true` | Auto-register volumes |
| Add ECGroup Volumes to HS | ✅ Yes | `add_ecgroup_volumes = true` | Auto-register ECGroup |
| Custom Cloud-Init Scripts | ✅ Yes | `*_user_data` | Custom provisioning |
| **Auto-detect New Nodes** | ✅ Yes | Automatic | Detects & configures new storage/ECGroup nodes |
| **platformServices Discovery** | ✅ Yes | Automatic | Waits for NFS export discovery |
| **Volume Group Auto-Update** | ✅ Yes | Automatic | Adds new nodes to existing VG |

### Automatic Node Detection & Configuration

The Ansible module automatically detects when new Storage Servers or ECGroup nodes are added and re-runs configuration:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     AUTOMATIC NODE DETECTION WORKFLOW                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   terraform apply                                                           │
│         │                                                                   │
│         ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Terraform detects changes in:                                      │   │
│   │  • storage_instances (new storage servers)                          │   │
│   │  • ecgroup_nodes (new ECGroup nodes)                                │   │
│   │  • ecgroup_add_to_hammerspace (integration toggle)                  │   │
│   │  • add_storage_server_volumes (volume toggle)                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│         │                                                                   │
│         ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Ansible inventory.ini updated with new nodes                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│         │                                                                   │
│         ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Ansible job scripts run:                                           │   │
│   │  30-add-storage-nodes.sh    → Add nodes to Hammerspace              │   │
│   │  32-add-storage-volumes.sh  → Wait for discovery, add volumes       │   │
│   │  33-add-storage-volume-group.sh → Create/update volume group        │   │
│   │  34-create-storage-share.sh → Create share (if needed)              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Trigger | Condition | Action |
|---------|-----------|--------|
| `storage_instances_hash` | Storage servers added/removed | Re-configure storage nodes |
| `ecgroup_nodes_hash` | ECGroup nodes added/removed | Re-configure ECGroup cluster |
| `ecgroup_add_to_hs` | Integration enabled/disabled | Update Hammerspace integration |
| `add_storage_volumes` | Volume addition toggled | Update volume configuration |

### Ansible Job Scripts

| Script | Function | Key Features |
|--------|----------|--------------|
| `30-add-storage-nodes.sh` | Add nodes to Hammerspace | Registers storage servers as OTHER nodes |
| `32-add-storage-volumes.sh` | Add storage volumes | Waits for platformServices discovery with retry logic |
| `33-add-storage-volume-group.sh` | Manage volume group | Creates new VG or updates existing with new nodes |
| `34-create-storage-share.sh` | Create share | Idempotent, only adds confine objective if VG configured |

**Example: Adding Storage Servers Later**

```hcl
# Initial deployment (Hammerspace only)
deploy_components = ["hammerspace", "ansible"]
storage_instance_count = 0

# Later, add storage servers
deploy_components = ["hammerspace", "ansible", "storage"]
storage_instance_count = 2

# Run: terraform apply
# Ansible automatically:
# 1. Waits for platformServices discovery on new nodes
# 2. Adds new volumes to Hammerspace
# 3. Updates volume group to include new nodes
```

---

## Phased Deployment Support

| Scenario | Supported | How |
|----------|-----------|-----|
| Deploy Anvil first, DSX later | ✅ Yes | Set `dsx_count=0`, apply, then change to `dsx_count=N` |
| Use existing Anvil, deploy DSX | ✅ Yes | Set `use_existing_anvil=true` + `existing_anvil_ips` |
| Add more DSX nodes | ✅ Yes | Increase `dsx_count` and re-apply |
| Add ECGroup after Hammerspace | ✅ Yes | Add `"ecgroup"` to `deploy_components` |

---

## Security

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| SSH Key Authentication | ✅ Yes | `ssh_public_key` | SSH access |
| Custom Admin Password | ✅ Yes | `admin_user_password` | Hammerspace admin |
| Existing Anvil Password | ✅ Yes | `hammerspace_existing_anvil_password` | For existing clusters |
| Bastion CIDR Restrictions | ✅ Yes | `bastion_allowed_source_cidr_blocks` | Limit SSH access |
| OCI API Key Integration | ✅ Yes | `api_key`, `config_file` | Instance OCI access |

---

## Pre-flight Validation

| Check | Supported | Description |
|-------|-----------|-------------|
| **Networking Validation** | | |
| VCN Existence | ✅ Yes | Validates provided VCN exists |
| Subnet Exists in VCN | ✅ Yes | Validates subnet belongs to VCN |
| Network Configuration | ✅ Yes | Ensures VCN+subnet or create_networking |
| NAT Gateway Configuration | ✅ Yes | Validates NAT gateway for HA Anvil |
| **Instance Shape Availability** | | |
| Anvil Shape Availability | ✅ Yes | Checks shape exists in AD |
| DSX Shape Availability | ✅ Yes | Checks shape exists in AD |
| Client Shape Availability | ✅ Yes | Checks shape exists in AD |
| Storage Shape Availability | ✅ Yes | Checks shape exists in AD |
| ECGroup Shape Availability | ✅ Yes | Checks shape exists in AD |
| Ansible Shape Availability | ✅ Yes | Checks shape exists in AD |
| Bastion Shape Availability | ✅ Yes | Checks shape exists in AD |
| **Image Existence** | | |
| Hammerspace Image Exists | ✅ Yes | Validates image ID in region |
| Client Image Exists | ✅ Yes | Validates image ID in region |
| Storage Image Exists | ✅ Yes | Validates image ID in region |
| ECGroup Image Exists | ✅ Yes | Validates image ID in region |
| Ansible Image Exists | ✅ Yes | Validates image ID in region |
| Bastion Image Exists | ✅ Yes | Validates image ID in region |
| **Existing Infrastructure** | | |
| Existing Anvil Config | ✅ Yes | Validates IPs and password when using existing Anvil |
| Existing DSX Config | ✅ Yes | Validates IPs when using existing DSX |
| DSX Requires Anvil | ✅ Yes | Ensures DSX has an Anvil (new or existing) |

### Pre-flight Validation Benefits

- **Early Error Detection**: Errors are caught during `terraform plan` before any resources are created
- **Clear Error Messages**: Descriptive messages explain what's wrong and how to fix it
- **No Wasted Resources**: Avoids creating partial infrastructure due to invalid configuration
- **Existing Infrastructure Safety**: Validates existing Anvil/DSX configuration before attempting to use them

---

## Quick Reference: deploy_components Options

```hcl
# Deploy specific components
deploy_components = ["hammerspace"]                    # Only Hammerspace (Anvil + DSX)
deploy_components = ["hammerspace", "ansible"]         # Hammerspace + Ansible automation
deploy_components = ["hammerspace", "ecgroup"]         # Hammerspace + ECGroup
deploy_components = ["hammerspace", "storage"]         # Hammerspace + Storage servers
deploy_components = ["all"]                            # Everything

# Available component options:
# - "hammerspace" : Anvil metadata server + DSX data services
# - "ecgroup"     : RozoFS erasure-coded storage cluster
# - "storage"     : Generic storage server instances
# - "clients"     : NFS/SMB client instances
# - "ansible"     : Ansible automation controller
# - "bastion"     : SSH jump host
# - "all"         : Deploy all components
```

---

## Example Configurations

### Minimal Hammerspace Deployment (Anvil only)
```hcl
deploy_components = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count = 0
```

### Full Hammerspace with DSX
```hcl
deploy_components = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count = 2
```

### Using Existing Anvil
```hcl
deploy_components = ["hammerspace"]
hammerspace_use_existing_anvil = true
hammerspace_existing_anvil_ips = ["10.0.1.100"]
hammerspace_existing_anvil_password = "YourPassword"
hammerspace_anvil_count = 0
hammerspace_dsx_count = 2
```

### Hammerspace + ECGroup Integration
```hcl
deploy_components = ["hammerspace", "ecgroup", "ansible"]
hammerspace_anvil_count = 1
hammerspace_dsx_count = 0
ecgroup_node_count = 3
ecgroup_add_to_hammerspace = true
```

---

*Generated for Terraform-OCI project*
