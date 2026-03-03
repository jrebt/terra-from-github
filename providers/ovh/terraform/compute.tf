# ========================================
# Data sources compartidos
# ========================================

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

resource "openstack_compute_keypair_v2" "k3s_keypair" {
  name       = "${var.cluster_name}-keypair"
  public_key = var.ssh_public_key
}

# ========================================
# Security group rules (default SG)
# OVH quota: solo 1 SG por proyecto
# Anadimos reglas al "default" SG
# ========================================

data "openstack_networking_secgroup_v2" "default" {
  name = "default"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = data.openstack_networking_secgroup_v2.default.id
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = data.openstack_networking_secgroup_v2.default.id
}

resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = data.openstack_networking_secgroup_v2.default.id
}

# ========================================
# Modulos
# ========================================

module "network" {
  source       = "./modules/network"
  cluster_name = var.cluster_name
  subnet_cidr  = var.subnet_cidr
}

module "bastion" {
  source             = "./modules/bastion"
  cluster_name       = var.cluster_name
  image_id           = data.openstack_images_image_v2.ubuntu.id
  flavor             = var.flavor_bastion
  keypair_name       = openstack_compute_keypair_v2.k3s_keypair.name
  secgroup_name      = "default"
  ext_net_name       = module.network.ext_net_name
  private_network_id = module.network.private_network_id
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  depends_on = [module.network]
}

module "k3s" {
  source             = "./modules/k3s"
  cluster_name       = var.cluster_name
  image_id           = data.openstack_images_image_v2.ubuntu.id
  flavor             = var.flavor_master
  keypair_name       = openstack_compute_keypair_v2.k3s_keypair.name
  secgroup_name      = "default"
  private_network_id = module.network.private_network_id
  master_private_ip  = "10.0.0.10"
  ssh_public_key     = var.ssh_public_key

  depends_on = [module.network]
}
