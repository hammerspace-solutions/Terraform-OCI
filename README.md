# Terraform-OCI
This project uses Terraform to provision resources on Oracle Cloud Infrastructure (OCI). The deployment is modular, allowing you to deploy client machines, storage servers, and a Hammerspace environment either together or independently.

This project was originally written for internal Hammerspace use to size Hammerspace resources within AWS for inclusion in a LLM model for automated AI sizing. It has since been adapted for OCI and expanded to allow customers to deploy linux clients, linux storage servers, and Hammerspace Anvil's and DSX's for any use that they wish.

Guard-rails have been added to make sure that the deployments are as easy as possible for the uninitiated cloud user.

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Client Variables](#client-variables)
  - [Storage Server Variables](#storage-server-variables)
  - [Hammerspace Variables](#hammerspace-variables)
  - [ECGroup Variables](#ecgroup-variables)
  - [Ansible Variables](#ansible-variables)
- [Infrastructure Guardrails and Validation](#infrastructure-guardrails-and-validation)
- [Dealing with OCI Capacity and Timeouts](#dealing-with-oci-capacity-and-timeouts)
  - [Controlling API Retries (`max_retries`)](#controlling-api-retries-max_retries)
  - [Controlling Capacity Timeouts](#controlling-capacity-timeouts)
  - [Understanding the Timeout Behavior](#understanding-the-timeout-behavior)
  - [Important Warning on Capacity Reservation Billing](#important-warning-on-capacity-reservation-billing)
- [Required OCI Policies for Dynamic Groups](#required-oci-policies-for-dynamic-groups)
- [Securely Accessing Instances](#securely-accessing-instances)
  - [Option 1: Bastion Host (Recommended)](#option-1-bastion-host-recommended)
  - [Option 2: OCI Identity and Access Management (Most Secure)](#option-2-oci-identity-and-access-management-most-secure)
- [Prerequisites](#prerequisites)
- [How to Use](#how-to-use)
  - [Local Development Setup (OCI Config)](#local-development-setup-oci-config)
- [Important Note on Capacity Reservation Deletion](#important-note-on-capacity-reservation-deletion)
- [Outputs](#outputs)
- [Modules](#modules)

## Configuration

Configuration is managed through `terraform.tfvars` by setting values for the variables defined in `variables.tf`.

### Global Variables

These variables apply to the overall deployment:

* `region`: OCI region for all resources (Default: "uk-london-1").
* `compartment_ocid`: (Required) OCID of the compartment where resources will be created.
* `vcn_id`: (Required) OCID of the VCN (Virtual Cloud Network) for all resources.
* `subnet_id`: (Required) OCID of the subnet for resources. The Availability Domain is automatically derived from this subnet.
* `ad_number`: Availability Domain number (1, 2, or 3) (Default: 1).
* `assign_public_ip`: If `true`, assigns a public IP address to all created compute instances. If `false`, only a private IP will be assigned. (Default: `false`).
* `ssh_public_key`: (Required) SSH public key for instance access.
* `tags`: Common tags to apply to all resources (Default: `{}`).
* `project_name`: (Required) Project name used for tagging and resource naming.
* `ssh_keys_dir`: A local directory for public SSH key files (`.pub`). The startup script automatically adds these keys to the `authorized_keys` file on all servers. (Default: `"./ssh_keys"`).
* `deploy_components`: List of components to deploy (e.g., `["clients", "storage"]` or `["all"]`) (Default: `["all"]`).
* `fault_domain`: (Optional) Fault domain name for instance placement.

### OCI Authentication Variables

These variables configure authentication with OCI:

* `tenancy_ocid`: (Required) OCID of your tenancy.
* `user_ocid`: (Required) OCID of the user account.
* `fingerprint`: (Required) Fingerprint of the public key associated with the user.
* `private_key_path`: (Required) Path to the private key file.

---

## Component Variables

### Client Variables

These variables configure the client instances and are prefixed with `clients_` in your `terraform.tfvars` file.

* `clients_instance_count`: Number of client instances (Default: `1`).
* `clients_image_id`: (Required) OCID of the image for client instances.
* `clients_instance_shape`: Instance shape for clients (Default: `"VM.Standard.E4.Flex"`).
* `clients_ocpus`: Number of OCPUs for client instances (for Flex shapes) (Default: `8`).
* `clients_memory_gbs`: Amount of memory in GBs for client instances (for Flex shapes) (Default: `128`).
* `clients_boot_volume_size`: Boot volume size (GB) (Default: `50`).
* `clients_boot_volume_type`: Boot volume attachment type (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `clients_block_volume_count`: Number of extra block volumes per client (Default: `2`).
* `clients_block_volume_size`: Size of each block volume (GB) (Default: `100`).
* `clients_block_volume_type`: Type of block volume attachment (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `clients_block_volume_throughput`: Throughput for block volumes (MB/s) - for performance tiers.
* `clients_block_volume_iops`: IOPS for block volumes - for performance tiers.
* `clients_user_data`: Cloud-init user data script for clients.
* `clients_target_user`: Default system user for client instances (Default: `"opc"`).

---

### Storage Server Variables

These variables configure the storage server instances and are prefixed with `storage_` in your `terraform.tfvars` file.

* `storage_instance_count`: Number of storage instances (Default: `1`).
* `storage_image_id`: (Required) OCID of the image for storage instances.
* `storage_instance_shape`: Instance shape for storage (Default: `"VM.Standard.E4.Flex"`).
* `storage_ocpus`: Number of OCPUs for storage instances (for Flex shapes) (Default: `8`).
* `storage_memory_gbs`: Amount of memory in GBs for storage instances (for Flex shapes) (Default: `128`).
* `storage_boot_volume_size`: Boot volume size (GB) (Default: `100`).
* `storage_boot_volume_type`: Boot volume attachment type (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `storage_block_volume_count`: Number of extra block volumes per server for RAID (Default: `2`).
* `storage_raid_level`: RAID level to configure: `raid-0`, `raid-5`, or `raid-6` (Default: `"raid-0"`).
* `storage_block_volume_size`: Size of each block volume (GB) (Default: `200`).
* `storage_block_volume_type`: Type of block volume attachment (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `storage_block_volume_throughput`: Throughput for block volumes (MB/s) - for performance tiers.
* `storage_block_volume_iops`: IOPS for block volumes - for performance tiers.
* `storage_user_data`: Cloud-init user data script for storage.
* `storage_target_user`: Default system user for storage instances (Default: `"opc"`).

---

### Hammerspace Variables

These variables configure the Hammerspace deployment and are prefixed with `hammerspace_` in `terraform.tfvars`.

* **`hammerspace_profile_id`**: Controls Instance Principal configuration.
    * **For users with restricted OCI permissions**: An admin must pre-create a Dynamic Group and provide its name here. Terraform will use the existing configuration.
    * **For admin users**: Leave this variable as `""` (blank). Terraform will use the default instance principal configuration.
* **`hammerspace_anvil_security_group_id`**: (Optional) The OCID of a pre-existing network security group to attach to the Anvil nodes. If left blank, the module will create and configure a new security group.
* **`hammerspace_dsx_security_group_id`**: (Optional) The OCID of a pre-existing network security group to attach to the DSX nodes. If left blank, the module will create and configure a new security group.
* `hammerspace_image_id`: (Required) OCID of the image for Hammerspace instances.
* `hammerspace_anvil_count`: Number of Anvil instances (0=none, 1=standalone, 2=HA) (Default: `0`).
* `hammerspace_sa_anvil_destruction`: Safety switch to allow destruction of standalone Anvil (Default: `false`).
* `hammerspace_anvil_instance_shape`: Instance shape for Anvil (Default: `"VM.Standard.E4.Flex"`).
* `hammerspace_anvil_ocpus`: Number of OCPUs for Anvil instances (for Flex shapes) (Default: `12`).
* `hammerspace_anvil_memory_gbs`: Amount of memory in GBs for Anvil instances (for Flex shapes) (Default: `192`).
* `hammerspace_dsx_instance_shape`: Instance shape for DSX nodes (Default: `"VM.Standard.E4.Flex"`).
* `hammerspace_dsx_ocpus`: Number of OCPUs for DSX instances (for Flex shapes) (Default: `2`).
* `hammerspace_dsx_memory_gbs`: Amount of memory in GBs for DSX instances (for Flex shapes) (Default: `32`).
* `hammerspace_dsx_count`: Number of DSX instances (Default: `1`).
* `hammerspace_anvil_meta_disk_size`: Metadata disk size in GB for Anvil (Default: `100`).
* `hammerspace_anvil_meta_disk_type`: Type of block volume attachment for Anvil metadata disk (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `hammerspace_anvil_meta_disk_throughput`: Throughput for Anvil metadata disk (MB/s) - for performance tiers.
* `hammerspace_anvil_meta_disk_iops`: IOPS for Anvil metadata disk - for performance tiers.
* `hammerspace_dsx_block_volume_size`: Size of each data volume per DSX node (Default: `100`).
* `hammerspace_dsx_block_volume_type`: Type of block volume attachment for DSX data volumes (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `hammerspace_dsx_block_volume_iops`: IOPS for each DSX data volume - for performance tiers.
* `hammerspace_dsx_block_volume_throughput`: Throughput for each DSX data volume (MB/s) - for performance tiers.
* `hammerspace_dsx_block_volume_count`: Number of data block volumes per DSX instance (Default: `1`).
* `hammerspace_dsx_add_vols`: Add non-boot block volumes as Hammerspace storage (Default: `true`).

---

### ECGroup Variables

These variables configure the ECGroup deployment and are prefixed with `ecgroup_` in `terraform.tfvars`.

* `ecgroup_node_count`: Number of ECGroup nodes to create (Default: `0`).
* `ecgroup_image_id`: OCID of the image for ECGroup instances (fallback if region mapping fails).
* `ecgroup_instance_shape`: Instance shape for ECGroup nodes (Default: `"VM.Standard.E4.Flex"`).
* `ecgroup_ocpus`: Number of OCPUs for ECGroup instances (for Flex shapes) (Default: `16`).
* `ecgroup_memory_gbs`: Amount of memory in GBs for ECGroup instances (for Flex shapes) (Default: `256`).
* `ecgroup_boot_volume_size`: Boot volume size (GB) for ECGroup nodes (Default: `100`).
* `ecgroup_boot_volume_type`: Boot volume attachment type for ECGroup nodes (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `ecgroup_metadata_volume_size`: Size of the ECGroup metadata block volume in GB (Default: `50`).
* `ecgroup_metadata_volume_type`: Type of block volume attachment for ECGroup metadata (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `ecgroup_metadata_volume_throughput`: Throughput for metadata block volumes (MB/s).
* `ecgroup_metadata_volume_iops`: IOPS for metadata block volumes.
* `ecgroup_storage_volume_count`: Number of ECGroup storage volumes to attach to each node (Default: `0`).
* `ecgroup_storage_volume_size`: Size of each storage block volume (GB) for ECGroup nodes (Default: `0`).
* `ecgroup_storage_volume_type`: Type of block volume attachment for ECGroup storage (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `ecgroup_storage_volume_throughput`: Throughput for each storage block volume (MB/s).
* `ecgroup_storage_volume_iops`: IOPS for each storage block volume.
* `ecgroup_user_data`: Cloud-init user data script for ECGroup.

---

### Ansible Variables

These variables configure the Ansible controller instance and its playbook. Prefixes are `ansible_` where applicable.

* `ansible_instance_count`: Number of Ansible instances (Default: `1`).
* `ansible_image_id`: (Required) OCID of the image for Ansible instances.
* `ansible_instance_shape`: Instance shape for Ansible (Default: `"VM.Standard.E4.Flex"`).
* `ansible_ocpus`: Number of OCPUs for Ansible instances (for Flex shapes) (Default: `8`).
* `ansible_memory_gbs`: Amount of memory in GBs for Ansible instances (for Flex shapes) (Default: `128`).
* `ansible_boot_volume_size`: Boot volume size (GB) (Default: `100`).
* `ansible_boot_volume_type`: Boot volume attachment type (`iscsi` or `paravirtualized`) (Default: `"paravirtualized"`).
* `ansible_user_data`: Cloud-init user data script for Ansible.
* `ansible_target_user`: Default system user for Ansible instances (Default: `"opc"`).
* `volume_group_name`: The name of the volume group for Hammerspace storage, used by the Ansible playbook. (Default: `"vg-auto"`).
* `share_name`: (Required) The name of the share to be created on the storage, used by the Ansible playbook.

---

## Infrastructure Guardrails and Validation

To prevent common errors and ensure a smooth deployment, this project includes several "pre-flight" checks that run during the `terraform plan` phase. If any of these checks fail, the plan will stop with a clear error message before any resources are created.

* **Network Validation**:
    * **VCN and Subnet Existence**: Verifies that the `vcn_id` and `subnet_id` you provide correspond to real resources in the target OCI region.
    * **Subnet in VCN**: Confirms that the provided subnet is actually part of the specified VCN.

* **Resource Availability Validation**:
    * **Instance Shape Availability**: Checks if your chosen instance shapes (e.g., `VM.Standard.E4.Flex`) are offered by OCI in the specific Availability Domain of your subnet.
    * **Image Existence**: Verifies that the image OCIDs you provide for clients, storage, Hammerspace, ECGroup, and Ansible are valid and accessible in the target region.

* **Capacity and Provisioning Guardrails**:
    * **Compute Capacity Reservations**: Before attempting to create instances, Terraform will first try to reserve the necessary capacity. If OCI cannot fulfill the reservation due to a real-time capacity shortage, the `terraform apply` will fail quickly instead of hanging.
    * **Destruction Safety**: The standalone Anvil instance is protected by a `lifecycle` block to prevent accidental deletion. You must explicitly set `hammerspace_sa_anvil_destruction = true` to destroy it.

---

## Dealing with OCI Capacity and Timeouts

When deploying large or specialized compute instances, you may encounter capacity-related errors from OCI. This project includes several advanced features to manage this issue and provide predictable behavior.

### Controlling API Retries (`max_retries`)

The OCI provider will automatically retry certain API errors. While normally helpful, this can cause the `terraform apply` command to hang for many minutes before finally failing.

To get immediate feedback, you can instruct the provider not to retry. In your root `main.tf`, configure the `provider` block:

```terraform
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
  
  # Fail immediately on the first retryable error instead of hanging.
  # Set to 0 for debugging, or a small number like 2 for production.
  max_retries = 0
}
```
Setting `max_retries = 0` is excellent for debugging capacity issues, as it ensures the `apply` fails on the very first error.

### Controlling Capacity Timeouts

To prevent long hangs, this project first creates Compute Capacity Reservations to secure hardware before launching instances. The timeout behavior is controlled by OCI's default settings.

### Understanding the Timeout Behavior

It is critical to understand how these settings interact. Even with `max_retries = 0`, you may see Terraform wait for the full duration of the capacity reservation creation.

This is not a bug; it is the fundamental behavior of the OCI Capacity Reservation system:
1.  Terraform sends the request to OCI to create the reservation.
2.  OCI acknowledges the request and places the reservation in a **`PROVISIONING`** state. The API call itself succeeds, so `max_retries` has no effect.
3.  OCI now searches for physical hardware to fulfill your request in the background.
4.  The Terraform provider enters a "waiter" loop, polling OCI every ~15 seconds, asking, "Is the reservation `ACTIVE` yet?"
5.  The `Still creating...` message you see during `terraform apply` corresponds to this waiting period.

### Important Warning on Capacity Reservation Billing

> **Warning:** Compute Capacity Reservations begin to incur charges at the standard rate as soon as they are successfully created, **whether you are running an instance in them or not.**
>
> `terraform destroy` is designed to cancel these reservations. However, if the `destroy` command fails for any reason (e.g., an instance fails to terminate), the reservation will be "orphaned" and **will continue to incur charges**.
>
> If you encounter a failed `destroy`, it is crucial to **run `terraform destroy` a second time** to ensure all resources, including the capacity reservations, are properly cleaned up.

---

## Required OCI Policies for Dynamic Groups

If you are using the `hammerspace_profile_id` variable to provide a pre-existing Dynamic Group, the group must have policies attached with the following permissions.

**Summary for OCI Administrators:**
1.  Create a Dynamic Group with matching rules for your instances.
2.  Create a Policy with the statements below.
3.  Attach the policy to the compartment where your instances will run.
4.  Provide the name of the **Dynamic Group** to the user running Terraform.

**Required OCI Policy Statements:**
```
Allow dynamic-group <your-group-name> to read instances in compartment <your-compartment>
Allow dynamic-group <your-group-name> to read instance-configurations in compartment <your-compartment>
Allow dynamic-group <your-group-name> to manage private-ips in compartment <your-compartment>
Allow dynamic-group <your-group-name> to use block-storage-family in compartment <your-compartment>
```

**Permission Breakdown:**
* **read instances**: Allows instances to discover each other's state and configuration.
* **read instance-configurations**: Allows access to instance metadata and configuration.
* **manage private-ips**: **(Crucial for HA)** Allows an Anvil node to take over the floating cluster IP address from its partner during a failover.
* **use block-storage-family**: Required for instances to access and manage attached block volumes.

---

## Securely Accessing Instances

For production or security-conscious environments, allowing SSH access from the entire internet (`0.0.0.0/0`) is not recommended. The best practice is to limit access to a controlled entry point.

### Option 1: Bastion Host (Recommended)

A Bastion Host (or "jump box") is a single, hardened compute instance that lives in a public subnet and is the only instance that accepts connections from the internet (or a corporate VPN). Users first SSH into the bastion host, and from there, they can "jump" to other instances in private subnets using their private IP addresses.

This project supports this pattern through Network Security Groups. You would:
1.  Create a network security group for your bastion host.
2.  Configure the ingress rules to allow SSH traffic *only* from resources within that bastion host security group.

### Option 2: OCI Identity and Access Management (Most Secure)

A more modern approach is to use OCI's Instance Console Connections or OCI Cloud Shell. These services allow you to get a secure connection to your instances without opening **any** inbound ports (not even port 22). Access is controlled entirely through OCI IAM policies, providing the highest level of security and auditability.

---

## Prerequisites

Before running this Terraform configuration, please ensure the following one-time setup tasks are complete for the target OCI tenancy.

* **Install Tools**: You must have [Terraform](https://developer.hashicorp.com/terraform/downloads) and the [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm) installed and configured on your local machine.
* **OCI Authentication**: Configure your OCI credentials either through the OCI CLI (`oci setup config`) or by manually creating the configuration files. You'll need your tenancy OCID, user OCID, fingerprint, and private key file.
* **OCI Marketplace Subscription**: This configuration may use partner images (e.g., for Hammerspace) which require acceptance of terms in the OCI Marketplace. If you encounter subscription-related errors during `terraform apply`, you must visit the OCI Marketplace, sign in to your tenancy, and accept the terms for the required products.

---

## How to Use

1.  **Initialize**: `terraform init`
2.  **Configure**: Create a `terraform.tfvars` file to set your desired variables. At a minimum, you must provide authentication variables (`tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key_path`), `project_name`, `compartment_ocid`, `vcn_id`, `subnet_id`, `ssh_public_key`, and the required `*_image_id` variables.
3.  **Plan**: `terraform plan`
4.  **Apply**: `terraform apply`

### Local Development Setup (OCI Config)
To use a named profile from your `~/.oci/config` file for local runs without affecting the CI/CD pipeline, you should use a local override file. This prevents your personal credentials profile from being committed to source control.

1.  **Create an override file**: In the root directory of the project, create a new file named `local_override.tf`.
2.  **Add the provider configuration**: Place the following code inside `local_override.tf`, replacing `"your-profile-name"` with your actual profile name.

    ```terraform
    # Terraform-OCI/local_override.tf
    # This file is for local development overrides and should not be committed.

    provider "oci" {
      config_file_profile = "your-profile-name"
    }
    ```
When you run Terraform locally, it will automatically merge this file with `main.tf`, using your profile. The CI/CD system will not have this file and will correctly fall back to using the credentials stored in its environment variables.

---

## Important Note on Capacity Reservation Deletion

When you run `terraform destroy` on a configuration that created capacity reservations, you may see an error like this:

`Error: The capacity reservation ... is in use and may not be deleted.`

This is normal and expected behavior due to a race condition in the OCI API. It happens because Terraform sends the requests to terminate the compute instances and delete the capacity reservation at nearly the same time. If the instances haven't fully terminated on the OCI backend, the API will reject the request to delete the reservation.

**The solution is to simply run `terraform destroy` a second time.** The first run will successfully terminate the instances, and the second run will then be able to successfully delete the now-empty capacity reservation.

---

## Outputs

After a successful `apply`, Terraform will provide the following outputs. Sensitive values will be redacted and can be viewed with `terraform output <output_name>`.

* `client_instances`: A list of non-sensitive details for each client instance (OCID, IP, Name).
* `client_private_ips`: A list of private IP addresses for client instances.
* `client_public_ips`: A list of public IP addresses for client instances (if assigned).
* `storage_instances`: A list of non-sensitive details for each storage instance.
* `storage_private_ips`: A list of private IP addresses for storage instances.
* `storage_public_ips`: A list of public IP addresses for storage instances (if assigned).
* `hammerspace_anvil`: **(Sensitive)** A list of detailed information for the deployed Anvil nodes.
* `hammerspace_dsx`: **(Sensitive)** A list of detailed information for the deployed DSX nodes.
* `hammerspace_anvil_private_ips`: A list of private IP addresses for the Hammerspace Anvil instances.
* `hammerspace_dsx_private_ips`: A list of private IP addresses for the Hammerspace DSX instances.
* `hammerspace_mgmt_url`: The URL to access the Hammerspace management interface.
* `ecgroup_nodes`: **(Sensitive)** A list of detailed information for the deployed ECGroup nodes.
* `ecgroup_private_ips`: A list of private IP addresses for ECGroup nodes.
* `ansible_details`: A list of details for the Ansible controller instances.
* `deployment_summary`: Summary of deployed components and their configuration.

---
## Modules

This project is structured into the following modules:
* **clients**: Deploys client compute instances with configurable block volumes.
* **storage_servers**: Deploys storage server compute instances with configurable RAID and block volume configurations.
* **hammerspace**: Deploys Hammerspace Anvil (metadata) and DSX (data) nodes with HA support.
* **ecgroup**: Deploys ECGroup nodes for erasure coding storage configurations.
* **ansible**: Deploys an Ansible controller instance which performs "Day 2" configuration tasks after the primary infrastructure is provisioned. Its key functions are:
    * **Hammerspace Integration**: It runs a playbook that connects to the Anvil's API to add the newly created storage servers as data nodes, create a volume group, and create a share.
    * **Passwordless SSH Setup**: It runs a second playbook that orchestrates a key exchange between all client and storage nodes, allowing them to SSH to each other without passwords for automated scripting.
    * **ECGroup Configuration**: It can configure ECGroup clusters for distributed storage workloads.
