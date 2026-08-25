# Kubernetes Cluster with Ansible

This repository manages K3s cluster deployment using `ansible-galaxy` to consume the upstream `k3s-ansible` playbook as a dependency.

## Playbooks

```sh
# Install K3s and kube-vip
ansible-playbook site.yml -i inventory.yml --ask-vault-pass
# Upgrade
ansible-playbook k3s.orchestration.upgrade -i inventory.yml --ask-vault-pass
# Reboot
ansible-playbook k3s.orchestration.reboot -i inventory.yml --ask-vault-pass
# Reset
ansible-playbook k3s.orchestration.reset -i inventory.yml --ask-vault-pass
```

## Vault Management

```sh
# Initial vault setup
ansible-vault create vault-globals.yml
# Add `k3s_token: <random-string>` to the vault

# View encrypted secrets
ansible-vault view vault-globals.yml --ask-vault-pass`
# Edit secrets (requires vault password)
ansible-vault edit vault-globals.yml --ask-vault-pass`

# Create .vault-password file (one-time setup)
echo "your-vault-password" > .vault-password
chmod 600 .vault-password

# Now playbooks work without --ask-vault-pass (vault password read from file)
# Will prompt for sudo password when needed
ansible-playbook k3s.orchestration.site -i inventory.yml
ansible-playbook k3s.orchestration.upgrade -i inventory.yml
ansible-playbook k3s.orchestration.reset -i inventory.yml
ansible-playbook k3s.orchestration.reboot -i inventory.yml
```

## Version Management

### k3s & Kubernetes

1. Update `k3s_version` in `inventory.yml`
1. `ansible-playbook k3s.orchestration.upgrade -i inventory.yml`

### k3s-ansible

The upstream `k3s-ansible` version is pinned in `requirements.yml`. To update:

1. Edit the `version` field in `requirements.yml`
2. Re-run: `ansible-galaxy install -r requirements.yml --force`

## Project Structure

```
.
├── requirements.yml           # Galaxy role/collection dependencies
├── inventory.yml              # Cluster node definitions (hosts and groups)
├── ansible.cfg                # Ansible configuration
├── group_vars/                # Variable overrides for groups
│   └── all-vault.yml          # Ansible-vault secrets
└── README.md                  # This file
```

## Prerequisites

- Ansible 2.10+
- SSH access to all nodes in the cluster
- **Sudo access** on all nodes (required for k3s installation/upgrades)
- Vault password to decrypt `vault-globals.yml`

## Installation

1. Clone this repository:
```bash
git clone <repo-url>
cd kubernetes-cluster-ansible
```

2. Install Galaxy dependencies:
```bash
ansible-galaxy install -r requirements.yml
```

This downloads the upstream `k3s-ansible` role from GitHub into your Galaxy cache directory.

## Configuration

### Inventory

Edit `inventory.yml` to define your cluster nodes and their roles:
- `k3s_master`: Control plane nodes
- `k3s_node`: Worker nodes
- `k3s_cluster`: Group containing all cluster members

### Variables

- **vault-globals.yml**: Contains encrypted secrets like `k3s_token`
- **group_vars/k3s_cluster.yml**: Cluster-wide configuration overrides (k3s version, network settings, etc.)
- **host_vars/**: Node-specific overrides if needed


3. Re-deploy: `ansible-playbook site.yml -i inventory.yml --ask-vault-pass`

## Additional Resources

- [K3s Documentation](https://docs.k3s.io/)
- [k3s-ansible on GitHub](https://github.com/k3s-io/k3s-ansible)
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Ansible Galaxy Documentation](https://docs.ansible.com/ansible/latest/user_guide/collections_using.html)
