# Terraform-OCI

Terraform infrastructure-as-code for deploying Hammerspace Global Data Environment on Oracle Cloud Infrastructure (OCI).

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Component Selection](#component-selection)
- [Deployment Scenarios](#deployment-scenarios)
  - [Scenario 1: Standalone Anvil Only](#scenario-1-standalone-anvil-only)
  - [Scenario 2: Anvil + DSX Nodes](#scenario-2-anvil--dsx-nodes)
  - [Scenario 3: Phased Deployment](#scenario-3-phased-deployment)
  - [Scenario 4: Use Existing Anvil](#scenario-4-use-existing-anvil)
  - [Scenario 5: Hammerspace + ECGroup](#scenario-5-hammerspace--ecgroup)
- [Networking Options](#networking-options)
- [Instance Shapes](#instance-shapes)
- [Placement Control](#placement-control)
- [Volume Groups & Shares](#volume-groups--shares)
- [Automatic Node Detection](#automatic-node-detection)
- [Outputs](#outputs)
- [Feature Matrix](#feature-matrix)
- [Pre-flight Validation](#pre-flight-validation)
- [Troubleshooting](#troubleshooting)
- [Clean Up](#clean-up)
- [File Structure](#file-structure)
- [License](#license)

---

## Overview

This Terraform project provides a modular, production-ready deployment of Hammerspace components on OCI, including:

- **Hammerspace Anvil** - Metadata controller (standalone or HA)
- **Hammerspace DSX** - Data services nodes
- **ECGroup (RozoFS)** - Erasure-coded distributed storage
- **Storage Servers** - Generic storage nodes
- **Ansible Controller** - Automated configuration management
- **Bastion Host** - Secure SSH jump host
- **Client Instances** - NFS/SMB client nodes

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                      OCI Region                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                       VCN                                         │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                                   Subnet                                    │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌─────────────┐      ┌──────────────────────────────────────────────────┐  │  │  │
│  │  │  │   Bastion   │      │              HAMMERSPACE CORE                    │  │  │  │
│  │  │  │  (Optional) │      │  ┌─────────────────────────────────────────────┐ │  │  │  │
│  │  │  │             │      │  │                  Anvil                      │ │  │  │  │
│  │  │  │  SSH Jump   │      │  │           (Metadata Controller)             │ │  │  │  │
│  │  │  │    Host     │      │  │                                             │ │  │  │  │
│  │  │  └─────────────┘      │  │   Standalone (1) or HA Mode (2 nodes)       │ │  │  │  │
│  │  │                       │  └──────────────────────┬──────────────────────┘ │  │  │  │
│  │  │                       │                         │                        │  │  │  │
│  │  │                       │           ┌─────────────┴─────────────┐          │  │  │  │
│  │  │                       │           ▼                           ▼          │  │  │  │
│  │  │                       │  ┌─────────────────┐       ┌─────────────────┐   │  │  │  │
│  │  │                       │  │   DSX Node 0    │       │   DSX Node N    │   │  │  │  │
│  │  │                       │  │   (Optional)    │  ...  │   (Optional)    │   │  │  │  │
│  │  │                       │  │                 │       │                 │   │  │  │  │
│  │  │                       │  │  Data Services  │       │  Data Services  │   │  │  │  │
│  │  │                       │  └────────┬────────┘       └────────┬────────┘   │  │  │  │
│  │  │                       │           │                         │            │  │  │  │
│  │  │                       │           ▼                         ▼            │  │  │  │
│  │  │                       │  ┌────────────────────────────────────────────┐  │  │  │  │
│  │  │                       │  │            Block Volumes (OCI)             │  │  │  │  │
│  │  │                       │  └────────────────────────────────────────────┘  │  │  │  │
│  │  │                       └──────────────────────────────────────────────────┘  │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌──────────────────────────────┐    ┌──────────────────────────────────┐   │  │  │
│  │  │  │     STORAGE BACKENDS         │    │      AUTOMATION & CLIENTS        │   │  │  │
│  │  │  │         (Optional)           │    │          (Optional)              │   │  │  │
│  │  │  │                              │    │                                  │   │  │  │
│  │  │  │  ┌────────────────────────┐  │    │  ┌────────────────────────────┐  │   │  │  │
│  │  │  │  │    ECGroup (RozoFS)    │  │    │  │    Ansible Controller      │  │   │  │  │
│  │  │  │  │                        │  │    │  │                            │  │   │  │  │
│  │  │  │  │  ┌──────┐ ┌──────┐     │  │    │  │  Automated Configuration   │  │   │  │  │
│  │  │  │  │  │Node 1│ │Node 2│ ... │  │    │  │  - Add storage nodes       │  │   │  │  │
│  │  │  │  │  └──────┘ └──────┘     │  │    │  │  - Create volume groups    │  │   │  │  │
│  │  │  │  │                        │  │    │  │  - Configure shares        │  │   │  │  │
│  │  │  │  │  Erasure-coded storage │  │    │  └────────────────────────────┘  │   │  │  │
│  │  │  │  └────────────────────────┘  │    │                                  │   │  │  │
│  │  │  │                              │    │  ┌────────────────────────────┐  │   │  │  │
│  │  │  │  ┌────────────────────────┐  │    │  │     Client Instances       │  │   │  │  │
│  │  │  │  │    Storage Servers     │  │    │  │                            │  │   │  │  │
│  │  │  │  │                        │  │    │  │  NFS/SMB mount points      │  │   │  │  │
│  │  │  │  │  Generic block storage │  │    │  │  for testing/workloads     │  │   │  │  │
│  │  │  │  │  with RAID support     │  │    │  └────────────────────────────┘  │   │  │  │
│  │  │  │  └────────────────────────┘  │    │                                  │   │  │  │
│  │  │  └──────────────────────────────┘    └──────────────────────────────────┘   │  │  │
│  │  │                                                                             │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              COMPONENT SUMMARY                                          │
├─────────────────────┬───────────┬───────────────────────────────────────────────────────┤
│ Component           │ Required  │ Description                                           │
├─────────────────────┼───────────┼───────────────────────────────────────────────────────┤
│ Anvil               │ Yes*      │ Metadata controller (* or use existing)               │
│ DSX Nodes           │ Optional  │ Hammerspace data services with block volumes          │
│ ECGroup (RozoFS)    │ Optional  │ Erasure-coded distributed storage backend             │
│ Storage Servers     │ Optional  │ Generic storage nodes with RAID support               │
│ Ansible Controller  │ Optional  │ Automated configuration and integration               │
│ Client Instances    │ Optional  │ NFS/SMB clients for testing                           │
│ Bastion Host        │ Optional  │ SSH jump host for secure access                       │
└─────────────────────┴───────────┴───────────────────────────────────────────────────────┘
```

## Prerequisites

### Required

- **[Terraform](https://developer.hashicorp.com/terraform/downloads)** >= 1.0.0
- **[OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)** configured with valid credentials
- **[OCI Account](https://cloud.oracle.com/)** with appropriate permissions
- **Hammerspace Images** available in your OCI tenancy

### OCI Credentials

Create or update `oci/config` with your OCI credentials:

```ini
[DEFAULT]
user=ocid1.user.oc1..xxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxx
region=us-sanjose-1
key_file=~/.oci/oci_api_key.pem
```

### Required Files

```
oci/
├── config              # OCI CLI configuration
├── oci_api_key.pem     # OCI API private key
└── oci_cli_rc          # (Optional) OCI CLI runtime config
```

## Quick Start

### 1. Clone and Configure

```bash
# Copy example configuration
cp example_terraform.tfvars.rename terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Minimum Required Variables

```hcl
# OCI Authentication
tenancy_ocid     = "ocid1.tenancy.oc1..xxxxx"
user_ocid        = "ocid1.user.oc1..xxxxx"
fingerprint      = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
private_key_path = "~/.oci/oci_api_key.pem"
compartment_ocid = "ocid1.compartment.oc1..xxxxx"
region           = "us-sanjose-1"

# Hammerspace
hammerspace_image_id   = "ocid1.image.oc1..xxxxx"
admin_user_password    = "YourSecurePassword"
ssh_public_key         = "ssh-rsa AAAA..."

# What to deploy
deploy_components      = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan (pre-flight validation runs here)
terraform plan

# Apply the configuration
terraform apply
```

> **Note**: Pre-flight validation checks run during `terraform plan` and will catch configuration errors (invalid images, unavailable shapes, missing existing infrastructure details) before any resources are created.

### 4. Access Hammerspace

After deployment, access the Hammerspace UI:

```
https://<anvil-public-ip>:8443
Username: admin
Password: <admin_user_password>
```

## Component Selection

Use `deploy_components` to select which components to deploy:

```hcl
# Deploy only Hammerspace (Anvil + optional DSX)
deploy_components = ["hammerspace"]

# Deploy Hammerspace with Ansible automation
deploy_components = ["hammerspace", "ansible"]

# Deploy Hammerspace with ECGroup storage backend
deploy_components = ["hammerspace", "ecgroup", "ansible"]

# Deploy everything
deploy_components = ["all"]
```

### Available Components

| Component | Description |
|-----------|-------------|
| `hammerspace` | Anvil metadata server + DSX data services |
| `ecgroup` | RozoFS erasure-coded storage cluster |
| `storage` | Generic storage server instances |
| `clients` | NFS/SMB client instances |
| `ansible` | Ansible automation controller |
| `bastion` | SSH jump host |
| `all` | Deploy all components |

## Deployment Scenarios

### Scenario 1: Standalone Anvil Only

Deploy just the metadata server to start:

```hcl
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
```

### Scenario 2: Anvil + DSX Nodes

Full Hammerspace deployment with data services:

```hcl
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 2

# DSX storage configuration
hammerspace_dsx_block_volume_count = 4
hammerspace_dsx_block_volume_size  = 500  # GB per volume
```

### Scenario 3: Phased Deployment

Deploy Anvil first, add DSX later:

```hcl
# Phase 1: Deploy Anvil only
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
```

```bash
terraform apply
```

```hcl
# Phase 2: Add DSX nodes (update terraform.tfvars)
hammerspace_dsx_count = 2
```

```bash
terraform apply  # Adds DSX without touching Anvil
```

### Scenario 4: Use Existing Anvil

Connect to a pre-existing Anvil deployment:

```hcl
deploy_components                   = ["hammerspace"]
hammerspace_use_existing_anvil      = true
hammerspace_existing_anvil_ips      = ["10.0.1.100"]
hammerspace_existing_anvil_password = "ExistingAnvilPassword"
hammerspace_anvil_count             = 0  # Don't create new Anvil
hammerspace_dsx_count               = 2  # Add DSX nodes
```

### Scenario 5: Hammerspace + ECGroup

Use erasure-coded RozoFS storage:

```hcl
deploy_components          = ["hammerspace", "ecgroup", "ansible"]
hammerspace_anvil_count    = 1
hammerspace_dsx_count      = 0
ecgroup_node_count         = 3
ecgroup_add_to_hammerspace = true
ecgroup_volume_group_name  = "ecg-vg"
ecgroup_share_name         = "ecg-share"
```

## Networking Options

### Create New VCN

```hcl
create_networking = true
vcn_cidr          = "10.0.0.0/16"
subnet_cidr       = "10.0.1.0/24"
```

### Use Existing VCN/Subnet

```hcl
create_networking = false
vcn_id            = "ocid1.vcn.oc1..xxxxx"
subnet_id         = "ocid1.subnet.oc1..xxxxx"
```

### Private Deployment (No Public IPs)

```hcl
assign_public_ip                     = false
nat_gateway_id                       = "ocid1.natgateway.oc1..xxxxx"
# OR
create_nat_gateway_for_existing_vcn  = true
```

## Instance Shapes

### Flex Shapes (Recommended)

```hcl
# Anvil
hammerspace_anvil_instance_shape = "VM.Standard.E4.Flex"
hammerspace_anvil_ocpus          = 12
hammerspace_anvil_memory_gbs     = 192

# DSX
hammerspace_dsx_instance_shape   = "VM.Standard.E4.Flex"
hammerspace_dsx_ocpus            = 8
hammerspace_dsx_memory_gbs       = 128
```

### Bare Metal (High Performance)

```hcl
hammerspace_anvil_instance_shape = "BM.DenseIO.E5.128"
```

## Placement Control

### Availability Domain

```hcl
ad_number = 1  # 1, 2, or 3 (region-dependent)
```

### Fault Domains

```hcl
# General fault domain for non-Anvil instances
fault_domain = "FAULT-DOMAIN-1"

# Anvil HA across fault domains
anvil_fault_domains = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2"]

# DSX distribution across fault domains (round-robin)
dsx_fault_domains = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"]
```

When `dsx_fault_domains` is specified, DSX instances are distributed across the fault domains in round-robin fashion. For example, with 6 DSX nodes and 3 fault domains, each fault domain gets 2 DSX nodes.

## Volume Groups & Shares

Configure how storage is organized in Hammerspace:

```hcl
# Storage Server configuration
volume_group_name          = "storage-vg"
share_name                 = "production-share"
add_storage_server_volumes = true

# ECGroup configuration
ecgroup_add_to_hammerspace = true
ecgroup_volume_group_name  = "ecgroup-vg"
ecgroup_share_name         = "ecgroup-share"
add_ecgroup_volumes        = true
```

## Automatic Node Detection

When you add new Storage Servers or ECGroup nodes to an existing deployment, the Ansible controller automatically detects the changes and re-runs configuration tasks.

### How It Works

1. **Terraform detects changes** - When you increase `storage_server_count` or `ecgroup_node_count`, Terraform updates the Ansible module triggers.
2. **Inventory updated** - The Ansible controller receives an updated inventory with new node IPs.
3. **Configuration re-runs** - The ansible_config_main.sh script automatically runs to configure new nodes.

### Example: Adding Storage Servers

```hcl
# Initial deployment
storage_server_count = 2
```

```bash
terraform apply
```

```hcl
# Later: Add more storage servers
storage_server_count = 4  # Changed from 2 to 4
```

```bash
terraform apply  # Ansible automatically detects and configures new nodes
```

### Trigger Mechanism

The Ansible module monitors these attributes for changes:

| Trigger | Description |
|---------|-------------|
| `storage_instances_hash` | SHA256 of storage server instance data |
| `ecgroup_nodes_hash` | SHA256 of ECGroup node hostnames |
| `ecgroup_instances_hash` | SHA256 of ECGroup instance IPs |
| `ecgroup_add_to_hs` | ECGroup Hammerspace integration flag |
| `add_storage_volumes` | Storage server volumes flag |

### Ansible Job Scripts

The Ansible controller runs these scripts to configure storage integration:

| Script | Function | Key Features |
|--------|----------|--------------|
| `32-add-storage-volumes.sh` | Adds block volumes to Hammerspace | platformServices discovery wait, retry logic |
| `33-add-storage-volume-group.sh` | Creates/updates volume groups | Auto-update existing VGs with new nodes |
| `34-create-storage-share.sh` | Creates NFS shares | Conditional volume group objectives |

### Automation Features

#### platformServices Discovery

When storage volumes are added, Hammerspace needs time to discover NFS exports on storage nodes. The automation includes:
- Initial check for nodes with discovered platformServices
- Automatic retry with up to 20 retries, 15-second intervals
- Prevents volume addition failures due to timing issues

#### Volume Group Auto-Update

When adding new storage servers to an existing deployment:
- Existing volume group is fetched via REST API
- New node locations are merged with existing configuration
- PUT request preserves all required fields (`uoid`, `internalId`, etc.)
- No manual intervention required

### Reconfiguration

When changes are detected:
- Updated inventory file uploaded to Ansible controller
- Environment variables file (`deploy_vars.env`) recreated
- Configuration script re-executed
- New nodes added to Hammerspace volume groups (if enabled)

## Outputs

After deployment, Terraform provides useful outputs:

```bash
terraform output

# Example outputs:
# anvil_management_url = "https://10.0.1.100:8443"
# anvil_private_ip     = "10.0.1.100"
# dsx_private_ips      = ["10.0.1.101", "10.0.1.102"]
```

## Feature Matrix

For a complete list of all supported features and configuration options, see:

**[FEATURE_MATRIX.md](./FEATURE_MATRIX.md)**

This includes:
- Component deployment options
- Networking features
- Availability & placement settings
- Instance configuration
- Storage configuration
- Volume groups & shares
- ECGroup (RozoFS) features
- Automation & integration
- Automatic node detection & configuration
- Phased deployment scenarios
- Security settings
- **Pre-flight validation checks**

## Pre-flight Validation

This Terraform configuration includes comprehensive pre-flight validation checks that catch configuration errors early, during `terraform plan`, before any resources are created.

### What Gets Validated

| Category | Checks Performed |
|----------|------------------|
| **Networking** | VCN exists, subnet belongs to VCN, network config valid, NAT gateway configured for HA |
| **Instance Shapes** | All shapes (Anvil, DSX, Client, Storage, ECGroup, Ansible, Bastion) available in selected AD |
| **Images** | All image OCIDs exist in the region |
| **Existing Infrastructure** | Anvil IPs and password provided when using existing, DSX IPs provided when using existing |
| **Dependencies** | DSX deployment requires an Anvil (new or existing) |

### Example Validation Errors

**Missing existing Anvil configuration:**
```
Error: Invalid existing Anvil configuration:

When hammerspace_use_existing_anvil = true, you must provide:
  - hammerspace_existing_anvil_ips (list of IP addresses)
  - hammerspace_existing_anvil_password (admin password)
```

**Shape not available in AD:**
```
Error: The specified Anvil instance shape (VM.Standard.E5.Flex) is not available
in the selected Availability Domain (AD-1).
```

**DSX without Anvil:**
```
Error: Invalid Hammerspace configuration:

DSX nodes require an Anvil metadata server. You must either:
  - Set hammerspace_anvil_count > 0 to deploy new Anvil(s)
  - Set hammerspace_use_existing_anvil = true with existing Anvil IPs
```

### Benefits

- **Early error detection** - Errors caught at `plan` time, not during resource creation
- **Clear error messages** - Descriptive messages explain exactly what's wrong
- **No wasted resources** - Avoid partial deployments due to invalid configuration
- **Faster iteration** - Fix issues before waiting for provisioning

---

## Troubleshooting

### Common Issues

#### "Out of host capacity" Error

```
Error: 500-InternalError, Out of host capacity
```

**Solution**: Try a different Availability Domain or Fault Domain:
```hcl
ad_number    = 2  # Try different AD
fault_domain = "FAULT-DOMAIN-3"  # Try different FD
```

#### "No Availability Domain match" Error

```
Error: no Availability Domain match for AD number: 2
```

**Solution**: Your region may have only 1 AD. Use `ad_number = 1`.

#### DSX Can't Connect to Anvil

Check that:
1. Anvil is fully initialized (wait 5-10 minutes after creation)
2. Security groups allow port 4505-4506 (Salt)
3. `hammerspace_existing_anvil_ips` is correct (if using existing)

#### SR-IOV Networking Issues

If instances can't reach OCI metadata service:
```hcl
hammerspace_anvil_enable_sriov = false  # Disable SR-IOV
hammerspace_dsx_enable_sriov   = false
```

### Logs Location

- **Anvil/DSX**: `/var/log/hammerspace/`
- **Ansible**: `/var/log/ansible_main_config.log`
- **Cloud-init**: `/var/log/cloud-init-output.log`

## Clean Up

```bash
# Destroy all resources
terraform destroy

# Destroy specific module
terraform destroy -target=module.ansible
terraform destroy -target=module.hammerspace
```

## File Structure

```
.
├── main.tf                    # Root module configuration
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output definitions
├── versions.tf                # Provider version constraints
├── terraform.tfvars           # Your configuration values
├── FEATURE_MATRIX.md          # Complete feature reference
├── README.md                  # This file
├── modules/
│   ├── hammerspace/           # Anvil + DSX deployment
│   ├── ecgroup/               # RozoFS cluster
│   ├── storage_servers/       # Generic storage
│   ├── clients/               # Client instances
│   ├── ansible/               # Automation controller
│   └── bastion/               # Jump host
├── templates/                 # Cloud-init scripts
└── oci/                       # OCI credentials
```

## License

Copyright (c) 2025-2026 Hammerspace, Inc

MIT License - See LICENSE file for details.

---

*For detailed feature information, see [FEATURE_MATRIX.md](./FEATURE_MATRIX.md)*
