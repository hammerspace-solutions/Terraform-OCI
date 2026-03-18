# modules/ansible/templates/inventory.tpl
# Ansible Inventory Template for OCI Infrastructure

[all:vars]
ansible_user=${target_user}
ansible_ssh_private_key_file=/home/${target_user}/.ssh/ansible_admin_key
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

%{ if length(target_nodes) > 0 ~}
[target_nodes]
%{ for node in target_nodes ~}
${node.name} ansible_host=${node.private_ip} instance_id=${node.id}
%{ endfor ~}
%{ endif ~}

%{ if length(storage_instances) > 0 ~}
[storage_servers]
%{ for instance in storage_instances ~}
${instance.name} ansible_host=${instance.private_ip} instance_id=${instance.id}
%{ endfor ~}
%{ endif ~}

%{ if length(anvil_instances) > 0 ~}
[anvil_nodes]
%{ for instance in anvil_instances ~}
${instance.name} ansible_host=${instance.private_ip} instance_id=${instance.id}
%{ endfor ~}
%{ endif ~}

%{ if length(ecgroup_nodes) > 0 ~}
[ecgroup_nodes]
%{ for i, node_ip in ecgroup_nodes ~}
ecgroup-node-${i + 1} ansible_host=${node_ip}
%{ endfor ~}
%{ endif ~}

[hammerspace:children]
anvil_nodes
storage_servers

[infrastructure:children]
target_nodes
storage_servers
anvil_nodes
ecgroup_nodes

---

# modules/ansible/templates/ansible.cfg.tpl
[defaults]
host_key_checking = False
inventory = inventory.ini
remote_user = ${target_user}
private_key_file = ${private_key_file}
timeout = 30
gathering = smart
fact_caching = memory
retry_files_enabled = False
log_path = /var/log/ansible.log

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False