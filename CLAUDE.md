# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OVH K3s Kubernetes cluster deployment using Terraform for infrastructure provisioning and Ansible for configuration management. Deploys a lightweight K3s cluster with ArgoCD on OVH Public Cloud (OpenStack-based).

## Repository Layout

```
ovh/terra-from-github-main/
├── .github/workflows/       # GitHub Actions CI/CD (6 workflows)
├── providers/ovh/
│   ├── terraform/           # HCL infrastructure definitions
│   │   ├── compute.tf       # VM instances, SSH keys, security groups
│   │   ├── providers.tf     # OVH + OpenStack provider config
│   │   ├── variables.tf     # Input variables (credentials, cluster params)
│   │   ├── versions.tf      # Provider version constraints
│   │   ├── outputs.tf       # Generates Ansible inventory from infra state
│   │   ├── terraform.tfvars # Variable values
│   │   └── templates/       # Cloud-init scripts (master/worker VM setup)
│   └── ansible/
│       ├── ansible.cfg
│       ├── playbooks/       # k3s-install, cluster-config, argocd-install
│       └── roles/           # k3s-master, k3s-worker, argocd
```

## Commands

All Terraform commands run from `ovh/terra-from-github-main/providers/ovh/terraform/`:

```bash
terraform init -upgrade
terraform validate
terraform fmt -check
terraform plan -detailed-exitcode
terraform apply -auto-approve
terraform destroy -auto-approve
```

Ansible playbooks run from `ovh/terra-from-github-main/providers/ovh/ansible/`:

```bash
ansible-playbook playbooks/k3s-install.yml
ansible-playbook playbooks/cluster-config.yml
ansible-playbook playbooks/argocd-install.yml
```

## Architecture

**Data flow**: GitHub Actions → Terraform (creates VMs on OVH/OpenStack) → cloud-init (UFW, packages) → Terraform outputs generate Ansible inventory → Ansible installs K3s + ArgoCD.

**Terraform layer**: Provisions a single master node (b2-7 flavor, Ubuntu 22.04) on OVH GRA11 region with public networking (Ext-Net). SSH keypair created as OpenStack resource. Worker nodes are defined but currently set to 0.

**Ansible layer**: Three sequential playbooks — K3s installation (v1.28.5+k3s1), cluster configuration, and ArgoCD deployment (v2.9.5). Inventory is dynamically generated from Terraform outputs and passed as a GitHub Actions artifact between jobs.

**Providers**: OVH (~> 0.50) and OpenStack (~> 1.54), requiring Terraform >= 1.7.0.

## CI/CD Workflows

- **terraform-plan.yml**: Runs on PRs to main — fmt check, validate, plan with PR comment output
- **terraform-apply.yml**: Runs on push to main — auto-applies changes
- **ovh-k3s-deploy.yml**: Manual dispatch with action input (plan/apply/destroy/clean). Orchestrates both Terraform and Ansible jobs with a 5-minute wait for instance startup
- **terraform-destroy.yml**: Manual dispatch requiring "destroy" confirmation input
- **cleanup-keypair.yml**: Manual SSH keypair removal from OVH
- **test-openstack-auth.yml**: Manual OpenStack credential validation

## Required Secrets

OVH API: `OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`
OpenStack: `OPENSTACK_TENANT_ID`, `OPENSTACK_USERNAME`, `OPENSTACK_PASSWORD`
SSH: `OVH_SSH_PUBLIC_KEY`, `OVH_SSH_PRIVATE_KEY`
State backend: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`

## Known Limitations

- Single master node only (hardcoded in compute.tf)
- Worker node provisioning is defined but disabled (count=0, Ansible tasks commented out)
- Default security group allows all traffic — no custom rules
- `StrictHostKeyChecking` disabled in Ansible and `insecure: true` in OpenStack provider
- Cloud-init relies on a fixed 5-minute wait in CI before Ansible runs
