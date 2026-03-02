# Security groups para bastion y k3s

# --- Bastion: solo SSH desde internet ---
resource "openstack_networking_secgroup_v2" "bastion" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Bastion: SSH from internet only"
}

resource "openstack_networking_secgroup_rule_v2" "bastion_ssh" {
  security_group_id = openstack_networking_secgroup_v2.bastion.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

# --- K3s: SSH solo desde red privada, web desde internet ---
resource "openstack_networking_secgroup_v2" "k3s" {
  name        = "${var.cluster_name}-k3s-sg"
  description = "K3s: SSH from private net, HTTP/S from internet"
}

resource "openstack_networking_secgroup_rule_v2" "k3s_ssh_private" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.subnet_cidr
}

resource "openstack_networking_secgroup_rule_v2" "k3s_api_private" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.subnet_cidr
}

resource "openstack_networking_secgroup_rule_v2" "k3s_http" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "k3s_https" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

# NodePort range para Kong LoadBalancer
resource "openstack_networking_secgroup_rule_v2" "k3s_nodeports" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
}

# Permitir todo trafico interno entre nodos del cluster
resource "openstack_networking_secgroup_rule_v2" "k3s_internal" {
  security_group_id = openstack_networking_secgroup_v2.k3s.id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.subnet_cidr
}
