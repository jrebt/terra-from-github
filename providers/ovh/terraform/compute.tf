# Obtener la imagen de Ubuntu
data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

# Crear keypair SSH
resource "openstack_compute_keypair_v2" "k3s_keypair" {
  provider   = openstack.ovh
  name       = "${var.cluster_name}-keypair"
  public_key = var.ssh_public_key
}

# Obtener la red pública
data "openstack_networking_network_v2" "public" {
  name = "Ext-Net"
}

# Security group para el cluster
resource "openstack_networking_secgroup_v2" "k3s_secgroup" {
  provider    = openstack.ovh
  name        = "${var.cluster_name}-secgroup"
  description = "Security group for K3s cluster"
}

# Regla SSH
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  provider          = openstack.ovh
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_secgroup.id
}

# Regla K3s API
resource "openstack_networking_secgroup_rule_v2" "k3s_api" {
  provider          = openstack.ovh
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_secgroup.id
}

# Regla HTTP
resource "openstack_networking_secgroup_rule_v2" "http" {
  provider          = openstack.ovh
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_secgroup.id
}

# Regla HTTPS
resource "openstack_networking_secgroup_rule_v2" "https" {
  provider          = openstack.ovh
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_secgroup.id
}

# Regla para comunicación interna del cluster
resource "openstack_networking_secgroup_rule_v2" "internal" {
  provider          = openstack.ovh
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.k3s_secgroup.id
  security_group_id = openstack_networking_secgroup_v2.k3s_secgroup.id
}

# Master nodes
resource "openstack_compute_instance_v2" "k3s_master" {
  count           = var.master_count
  provider        = openstack.ovh
  name            = "${var.cluster_name}-master-${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.flavor_master
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k3s_secgroup.name]

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-master.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = count.index + 1
  })
}

# Worker nodes
resource "openstack_compute_instance_v2" "k3s_worker" {
  count           = var.worker_count
  provider        = openstack.ovh
  name            = "${var.cluster_name}-worker-${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.flavor_worker
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k3s_secgroup.name]

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-worker.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = count.index + 1
  })
}
