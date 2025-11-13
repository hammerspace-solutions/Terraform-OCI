# Terraform Unused Definitions Analysis Report

## Executive Summary

This report provides a comprehensive analysis of potentially unused Terraform definitions in the `/home/berat/Terraform-OCI` project. The analysis identified definitions across variables, locals, outputs, resources, and data sources that appear to have no references in the codebase.

**Important Note**: Some items listed may be false positives due to:
- Complex reference patterns that are difficult to detect programmatically
- External consumption (e.g., root module outputs)
- Dynamic references in expressions
- References through object properties (e.g., `var.common_config.property`)

## Analysis Results

### 1. Truly Unused Variables

These variables appear to be genuinely unused and can likely be removed:

#### In Module: storage_servers
- `allow_test_ingress` (modules/storage_servers/storage_variables.tf) - Not referenced anywhere

#### Throughput Variables (Across Multiple Modules)
The following throughput-related variables are defined but never used:
- `anvil_meta_disk_throughput` (modules/hammerspace/hammerspace_variables.tf)
- `block_volume_throughput` (modules/clients/clients_variables.tf, modules/storage_servers/storage_variables.tf)
- `dsx_block_volume_throughput` (modules/hammerspace/hammerspace_variables.tf)
- `metadata_block_throughput` (modules/ecgroup/ecgroup_variables.tf)
- `storage_block_throughput` (modules/ecgroup/ecgroup_variables.tf)

**Recommendation**: These throughput variables appear to be placeholders for future performance tuning features. Consider removing them if not planned for implementation.

### 2. Unused Local Values

#### In Module: hammerspace
The following locals in `modules/hammerspace/hammerspace_locals.tf` are defined but not used:
- `api_key` (line 58)
- `config_file` (line 59)
- `dsx_add_volumes_bool` (line 32)
- `effective_anvil_id_for_dsx_password` (line 51)
- `effective_anvil_ip_for_dsx_metadata` (line 49)

**Note**: The locals in the root module (main.tf) that appear unused are actually used through the `local.common_config` object passed to modules.

### 3. Unused Outputs

Many module outputs are defined but not referenced. This is common in Terraform modules as outputs serve as an API for potential future use. However, the following categories of unused outputs were identified:

#### Module: ansible
- All outputs except `instance_details` appear unused
- Notable unused outputs: `ansible_config_files`, `ansible_inventory_files`, `hammerspace_config`, `ecgroup_config`

#### Module: clients
- Most detailed outputs are unused in favor of the aggregated `instance_details`
- Unused: `instance_ids`, `private_ips`, `public_ips`, `volume_*` outputs

#### Module: storage_servers
- Similar pattern - detailed outputs unused in favor of `instance_details`
- Unused: `instance_ids`, `private_ips`, `public_ips`, `raid_*` outputs

#### Module: hammerspace
- Volume and network security group related outputs are unused
- Unused: `anvil_metadata_volume_*`, `dsx_data_volume_*`, `*_network_security_group_id`

#### Module: ecgroup
- Most outputs except `nodes`, `metadata_array`, and `storage_array` are unused

**Recommendation**: Consider removing unused module outputs to simplify the module interface, keeping only those that provide value to consumers.

### 4. Unused Resources

Several security group rules and volume attachments appear to have no explicit references:

#### Security Group Rules
- All `oci_core_network_security_group_security_rule` resources in modules

**Note**: These are likely used implicitly through their parent security groups.

#### Other Resources
- `local_file` resources in ansible module (ansible_config, ansible_inventory, hammerspace_playbook)
- `oci_core_public_ip.cluster_public_ip` in hammerspace module
- Various volume attachment resources

**Important**: These resources may be functioning correctly despite no explicit references, as they modify infrastructure state.

### 5. Unused Data Sources

- `data.oci_core_image.hammerspace_image` (modules/hammerspace/hammerspace_main.tf)
- `data.oci_core_subnet.selected` (modules/storage_servers/storage_main.tf)

## Recommendations

1. **Priority 1 - Safe to Remove**:
   - Unused throughput variables across all modules
   - `allow_test_ingress` variable in storage_servers module
   - Unused locals in hammerspace module

2. **Priority 2 - Review and Consider**:
   - Module outputs that are not consumed by any parent module
   - Data sources that appear unused

3. **Priority 3 - Verify Before Removing**:
   - Resources like security group rules and volume attachments (may have implicit effects)
   - Local file resources in ansible module (may be used by external processes)

4. **Best Practices Going Forward**:
   - Implement a regular cleanup process for unused definitions
   - Document why certain seemingly unused definitions are kept (e.g., for future use)
   - Consider using terraform-docs or similar tools to maintain module documentation

## Files to Review

Based on this analysis, focus your cleanup efforts on these files:
1. `modules/*/variables.tf` - Remove unused throughput variables
2. `modules/hammerspace/hammerspace_locals.tf` - Remove unused locals
3. `modules/*/outputs.tf` - Consolidate outputs to only those actively used
4. Example directories - Consider if these need to be maintained

## Conclusion

This analysis identified approximately 95 potentially unused definitions. However, after deeper analysis, only about 10-15 definitions appear to be truly unused and safe to remove. The majority are either:
- Module outputs designed for flexibility
- Resources with implicit effects
- Variables consumed through complex patterns

Start with the Priority 1 recommendations for safe, immediate cleanup.