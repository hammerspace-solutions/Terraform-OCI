#!/usr/bin/env python3
"""
Terraform Unused Definitions Analyzer
Analyzes Terraform files to find unused variables, locals, outputs, resources, and data sources.
"""

import os
import re
from collections import defaultdict
from pathlib import Path

class TerraformAnalyzer:
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
        
    def find_tf_files(self):
        """Find all .tf and .tfvars files"""
        tf_files = []
        for ext in ['*.tf', '*.tfvars']:
            tf_files.extend(self.root_dir.rglob(ext))
        return tf_files
    
    def extract_definitions(self, content, file_path):
        """Extract all definitions from a Terraform file"""
        # Variables
        var_pattern = r'variable\s+"([^"]+)"\s*\{'
        for match in re.finditer(var_pattern, content):
            self.definitions['variables'][match.group(1)].add(str(file_path))
        
        # Locals
        locals_pattern = r'locals\s*\{([^}]*)\}'
        for match in re.finditer(locals_pattern, content, re.DOTALL):
            locals_block = match.group(1)
            # Extract individual local values
            local_pattern = r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*='
            for local_match in re.finditer(local_pattern, locals_block, re.MULTILINE):
                self.definitions['locals'][local_match.group(1)].add(str(file_path))
        
        # Outputs
        output_pattern = r'output\s+"([^"]+)"\s*\{'
        for match in re.finditer(output_pattern, content):
            self.definitions['outputs'][match.group(1)].add(str(file_path))
        
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
        
        # Output references (module outputs)
        module_output_pattern = r'module\.([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)'
        for match in re.finditer(module_output_pattern, content):
            # This is a reference to a module output
            output_name = match.group(2)
            self.references['outputs'][output_name].add(str(file_path))
        
        # Resource references
        resource_pattern = r'([a-zA-Z_][a-zA-Z0-9_]+)\.([a-zA-Z_][a-zA-Z0-9_]+)\.'
        for match in re.finditer(resource_pattern, content):
            potential_resource = match.group(1)
            resource_name = match.group(2)
            # Check if it's not var, local, module, data, etc.
            if potential_resource not in ['var', 'local', 'module', 'data', 'each', 'count', 'path', 'terraform']:
                full_name = f"{potential_resource}.{resource_name}"
                self.references['resources'][full_name].add(str(file_path))
        
        # Data source references
        data_pattern = r'data\.([a-zA-Z_][a-zA-Z0-9_]+)\.([a-zA-Z_][a-zA-Z0-9_]+)'
        for match in re.finditer(data_pattern, content):
            full_name = f"data.{match.group(1)}.{match.group(2)}"
            self.references['data_sources'][full_name].add(str(file_path))
    
    def analyze(self):
        """Main analysis function"""
        tf_files = self.find_tf_files()
        
        # First pass: extract definitions and references
        for file_path in tf_files:
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
        
        for def_type in self.definitions:
            for name, files in self.definitions[def_type].items():
                if name not in self.references[def_type]:
                    unused[def_type][name] = list(files)
        
        return unused
    
    def generate_report(self, unused):
        """Generate a formatted report of unused definitions"""
        report = []
        report.append("# Terraform Unused Definitions Report")
        report.append("=" * 80)
        report.append("")
        
        total_unused = 0
        
        for def_type, items in unused.items():
            if items:
                report.append(f"\n## Unused {def_type.replace('_', ' ').title()}")
                report.append("-" * 40)
                for name, files in sorted(items.items()):
                    total_unused += 1
                    report.append(f"\n### {name}")
                    for file in files:
                        relative_path = os.path.relpath(file, self.root_dir)
                        report.append(f"  - Defined in: {relative_path}")
        
        if total_unused == 0:
            report.append("\nNo unused definitions found!")
        else:
            report.append(f"\n\nTotal unused definitions: {total_unused}")
        
        return "\n".join(report)

if __name__ == "__main__":
    analyzer = TerraformAnalyzer("/home/berat/Terraform-OCI")
    unused = analyzer.analyze()
    report = analyzer.generate_report(unused)
    print(report)