variable "cluster_name" {
  type = string
}

variable "image_id" {
  type = string
}

variable "flavor" {
  type    = string
  default = "b2-7"
}

variable "keypair_name" {
  type = string
}

variable "secgroup_name" {
  type = string
}

variable "private_network_id" {
  type = string
}

variable "master_private_ip" {
  type    = string
  default = "10.0.0.10"
}

variable "ssh_public_key" {
  type = string
}
