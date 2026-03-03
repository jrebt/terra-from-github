variable "cluster_name" {
  type = string
}

variable "image_id" {
  type = string
}

variable "flavor" {
  type    = string
  default = "d2-2"
}

variable "keypair_name" {
  type = string
}

variable "secgroup_name" {
  type = string
}

variable "ext_net_name" {
  type = string
}

variable "private_network_id" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for bastion"
  type        = string
  sensitive   = true
}
