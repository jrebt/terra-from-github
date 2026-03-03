# ========================================
# OVH API
# ========================================
variable "ovh_endpoint" {
  description = "OVH API endpoint"
  type        = string
  default     = "ovh-eu"
}

variable "ovh_application_key" {
  description = "OVH Application Key"
  type        = string
  sensitive   = true
}

variable "ovh_application_secret" {
  description = "OVH Application Secret"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH Consumer Key"
  type        = string
  sensitive   = true
}

# ========================================
# OpenStack
# ========================================
variable "openstack_tenant_id" {
  description = "OpenStack Tenant ID"
  type        = string
  sensitive   = true
}

variable "openstack_username" {
  description = "OpenStack username"
  type        = string
  sensitive   = true
}

variable "openstack_password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

# ========================================
# Proyecto
# ========================================
variable "service_name" {
  description = "OVH Public Cloud Project ID"
  type        = string
}

variable "region" {
  description = "OVH region"
  type        = string
  default     = "GRA11"
}

variable "cluster_name" {
  description = "K3s cluster name"
  type        = string
  default     = "k3s-prod"
}

variable "image_name" {
  description = "OS image name"
  type        = string
  default     = "Ubuntu 22.04"
}

variable "ssh_public_key" {
  description = "SSH public key for instances"
  type        = string
}

# ========================================
# Network
# ========================================
variable "subnet_cidr" {
  description = "Private subnet CIDR"
  type        = string
  default     = "10.0.0.0/24"
}

# ========================================
# Flavors
# ========================================
variable "flavor_bastion" {
  description = "Flavor for bastion (minimal)"
  type        = string
  default     = "d2-2"
}

variable "flavor_master" {
  description = "Flavor for K3s master"
  type        = string
  default     = "b2-7"
}

variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 0
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for bastion (reusable)"
  type        = string
  sensitive   = true
}
