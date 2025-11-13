#!/usr/bin/env python3
"""
Improved Terraform Unused Definitions Analyzer
Analyzes Terraform files to find unused variables, locals, outputs, resources, and data sources.
This version handles module boundaries and implicit references better.
"""

import os
import re
from collections import defaultdict
from pathlib import Path

class ImprovedTerraformAnalyzer:
    def __init__(self, root_dir):
        self.root_dir = Path(root_dir)
        self.definitions = {
            'variables': defaultdict(set),
            'locals': defaultdict(set),
            'outputs': defaultdict(set),
            'resources': defaultdict(set),
            'data_sources': defaultdict(set)
        }
        self.references = {
            'variables': defaultdict(set),
            'locals': defaultdict(set),
            'outputs': defaultdict(set),
            'resources': defaultdict(set),
            'data_sources': defaultdict(set)
        }
        # Track module paths for better analysis
        self.module_paths = set()
        self.module_outputs = defaultdict(dict)  # module_name -> output_name -> files
        
    def find_tf_files(self):
        """Find all .tf and .tfvars files"""
        tf_files = []
        for ext in ['*.tf', '*.tfvars']:
            tf_files.extend(self.root_dir.rglob(ext))
        
        # Identify module directories
        for f in tf_files:
            parts = f.parts
            if 'modules' in parts:
                module_idx = parts.index('modules')
                if module_idx + 1 < len(parts):
                    module_name = parts[module_idx + 1]
                    self.module_paths.add(module_name)
        
        return tf_files
    
    def get_module_name(self, file_path):
        """Extract module name from file path"""
        parts = Path(file_path).parts
        if 'modules' in parts:
            module_idx = parts.index('modules')
            if module_idx + 1 < len(parts):
                return parts[module_idx + 1]
        return None
    
    def extract_definitions(self, content, file_path):
        """Extract all definitions from a Terraform file"""
        module_name = self.get_module_name(file_path)
        
        # Variables
        var_pattern = r'variable\s+"([^"]+)"\s*\{'
        for match in re.finditer(var_pattern, content):
            var_name = match.group(1)
            self.definitions['variables'][var_name].add(str(file_path))
        
        # Locals - improved to handle multi-line locals blocks
        locals_pattern = r'locals\s*\{([^}]*\n)*[^}]*\}'
        for match in re.finditer(locals_pattern, content):
            locals_block = match.group(0)
            # Extract individual local values with better pattern
            local_pattern = r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=(?!=)'
            for local_match in re.finditer(local_pattern, locals_block, re.MULTILINE):
                local_name = local_match.group(1)
                self.definitions['locals'][local_name].add(str(file_path))
        
        # Outputs
        output_pattern = r'output\s+"([^"]+)"\s*\{'
        for match in re.finditer(output_pattern, content):
            output_name = match.group(1)
            self.definitions['outputs'][output_name].add(str(file_path))
            # Track module outputs separately
            if module_name:
                self.module_outputs[module_name][output_name] = str(file_path)
        
        # Resources
        resource_pattern = r'resource\s+"([^"]+)"\s+"([^"]+)"\s*\{'
        for match in re.finditer(resource_pattern, content):
            resource_type = match.group(1)
            resource_name = match.group(2)
            full_name = f"{resource_type}.{resource_name}"
            self.definitions['resources'][full_name].add(str(file_path))
        
        # Data sources
        data_pattern = r'data\s+"([^"]+)"\s+"([^"]+)"\s*\{'
        for match in re.finditer(data_pattern, content):
            data_type = match.group(1)
            data_name = match.group(2)
            full_name = f"data.{data_type}.{data_name}"
            self.definitions['data_sources'][full_name].add(str(file_path))
    
    def extract_references(self, content, file_path):
        """Extract all references from a Terraform file"""
        # Variable references
        var_pattern = r'var\.([a-zA-Z_][a-zA-Z0-9_]*)'
        for match in re.finditer(var_pattern, content):
            self.references['variables'][match.group(1)].add(str(file_path))
        
        # Local references
        local_pattern = r'local\.([a-zA-Z_][a-zA-Z0-9_]*)'
        for match in re.finditer(local_pattern, content):
            self.references['locals'][match.group(1)].add(str(file_path))
        
        # Module output references
        module_output_pattern = r'module\.([a-zA-Z_][a-zA-Z0-9_]*)\[?\d*\]?\.([a-zA-Z_][a-zA-Z0-9_]*)'
        for match in re.finditer(module_output_pattern, content):
            module_name = match.group(1)
            output_name = match.group(2)
            # Mark the output as referenced
            self.references['outputs'][output_name].add(str(file_path))
        
        # Resource references - improved pattern
        # Matches resource_type.resource_name but excludes known prefixes
        resource_ref_pattern = r'(?<![\w.])([a-zA-Z_][a-zA-Z0-9_]+)\.([a-zA-Z_][a-zA-Z0-9_]+)(?:\[|\.|$)'
        for match in re.finditer(resource_ref_pattern, content):
            potential_type = match.group(1)
            name = match.group(2)
            # Exclude known non-resource prefixes
            if potential_type not in ['var', 'local', 'module', 'data', 'each', 'count', 'path', 'terraform', 'null', 'self']:
                full_name = f"{potential_type}.{name}"
                # Check if this is actually a defined resource
                if full_name in self.definitions['resources']:
                    self.references['resources'][full_name].add(str(file_path))
        
        # Data source references
        data_pattern = r'data\.([a-zA-Z_][a-zA-Z0-9_]+)\.([a-zA-Z_][a-zA-Z0-9_]+)'
        for match in re.finditer(data_pattern, content):
            full_name = f"data.{match.group(1)}.{match.group(2)}"
            self.references['data_sources'][full_name].add(str(file_path))
        
        # Check for implicit references in dynamic content
        # Variables in string interpolations
        string_var_pattern = r'\$\{[^}]*var\.([a-zA-Z_][a-zA-Z0-9_]*)[^}]*\}'
        for match in re.finditer(string_var_pattern, content):
            self.references['variables'][match.group(1)].add(str(file_path))
        
        # Locals in string interpolations
        string_local_pattern = r'\$\{[^}]*local\.([a-zA-Z_][a-zA-Z0-9_]*)[^}]*\}'
        for match in re.finditer(string_local_pattern, content):
            self.references['locals'][match.group(1)].add(str(file_path))
    
    def analyze(self):
        """Main analysis function"""
        tf_files = self.find_tf_files()
        
        # First pass: extract definitions and references
        for file_path in tf_files:
            # Skip example directories
            if 'examples' in str(file_path):
                continue
                
            try:
                content = file_path.read_text()
                self.extract_definitions(content, file_path)
                self.extract_references(content, file_path)
            except Exception as e:
                print(f"Error reading {file_path}: {e}")
        
        # Find unused definitions
        unused = {
            'variables': {},
            'locals': {},
            'outputs': {},
            'resources': {},
            'data_sources': {}
        }
        
        # Special handling for different types
        for def_type in self.definitions:
            for name, files in self.definitions[def_type].items():
                # Skip if found in references
                if name in self.references[def_type]:
                    continue
                
                # Special cases
                skip = False
                
                # Skip outputs that might be used externally
                if def_type == 'outputs':
                    # Root module outputs are meant to be consumed externally
                    if any('modules' not in f for f in files):
                        continue
                
                # Skip certain common patterns
                if def_type == 'locals':
                    # Locals used in complex expressions might not be detected
                    if name in ['common_config']:  # This is commonly passed to modules
                        skip = True
                
                # Skip variables that might be set in tfvars files
                if def_type == 'variables' and any('example' not in f for f in files):
                    # Check if it's a module variable that might be set by the parent
                    if any('modules' in f for f in files):
                        # Module variables are often set by parent modules
                        continue
                
                if not skip:
                    unused[def_type][name] = list(files)
        
        return unused
    
    def generate_report(self, unused):
        """Generate a formatted report of unused definitions"""
        report = []
        report.append("# Terraform Unused Definitions Report (Improved Analysis)")
        report.append("=" * 80)
        report.append("\nNote: This analysis excludes:")
        report.append("- Root module outputs (consumed externally)")
        report.append("- Module input variables (set by parent modules)")
        report.append("- Files in 'examples' directories")
        report.append("")
        
        total_unused = 0
        
        categories = [
            ('variables', 'Variables'),
            ('locals', 'Local Values'),
            ('outputs', 'Outputs'),
            ('resources', 'Resources'),
            ('data_sources', 'Data Sources')
        ]
        
        for key, title in categories:
            items = unused[key]
            if items:
                report.append(f"\n## Unused {title}")
                report.append("-" * 40)
                
                # Group by module
                by_module = defaultdict(list)
                for name, files in sorted(items.items()):
                    for file in files:
                        module = self.get_module_name(file) or 'root'
                        by_module[module].append((name, file))
                
                for module, defs in sorted(by_module.items()):
                    if defs:
                        report.append(f"\n### Module: {module}")
                        for name, file in sorted(defs):
                            total_unused += 1
                            relative_path = os.path.relpath(file, self.root_dir)
                            report.append(f"  - {name} (in {relative_path})")
        
        if total_unused == 0:
            report.append("\nNo unused definitions found!")
        else:
            report.append(f"\n\nTotal unused definitions: {total_unused}")
            report.append("\nRecommendation: Review these definitions and remove if truly unused.")
            report.append("Some may be false positives due to complex reference patterns.")
        
        return "\n".join(report)

if __name__ == "__main__":
    analyzer = ImprovedTerraformAnalyzer("/home/berat/Terraform-OCI")
    unused = analyzer.analyze()
    report = analyzer.generate_report(unused)
    print(report)
    
    # Save report to file
    with open("/home/berat/Terraform-OCI/terraform_unused_definitions_report.txt", "w") as f:
        f.write(report)