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

variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "flavor_master" {
  description = "Flavor for master nodes"
  type        = string
  default     = "b2-7"
}

variable "flavor_worker" {
  description = "Flavor for worker nodes"
  type        = string
  default     = "b2-7"
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

# Credenciales OpenStack (se obtienen automáticamente del provider OVH)
# No necesitas añadirlas manualmente si usas el provider OVH configurado
