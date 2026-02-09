data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

resource "openstack_compute_keypair_v2" "k3s_keypair" {
  name       = "${var.cluster_name}-keypair"
  public_key = var.ssh_public_key
}

data "openstack_networking_network_v2" "public" {
  name = "Ext-Net"
}

# ========================================
# SECURITY GROUP PERSONALIZADO PARA K3s
# ========================================
resource "openstack_networking_secgroup_v2" "k3s_sg" {
  name        = "${var.cluster_name}-k3s-sg"
  description = "Security group optimizado para clúster K3s"
}

# SSH (22) - Acceso administrativo
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# Web (80-443) - Combinado HTTP/HTTPS en 1 regla
resource "openstack_networking_secgroup_rule_v2" "web" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# K3s API (6443)
resource "openstack_networking_secgroup_rule_v2" "k3s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# Comunicación interna nodos K3s (todos los puertos TCP)
resource "openstack_networking_secgroup_rule_v2" "internal_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_group_id   = openstack_networking_secgroup_v2.k3s_sg.id
  security_group_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# Comunicación interna nodos K3s (UDP para servicios como CoreDNS)
resource "openstack_networking_secgroup_rule_v2" "internal_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_group_id   = openstack_networking_secgroup_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k3s_sg.id
}

# ========================================
# INSTANCIAS CON NUEVO SECURITY GROUP
# ========================================
resource "openstack_compute_instance_v2" "k3s_master" {
  count           = var.master_count
  name            = "${var.cluster_name}-master-${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.flavor_master
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k3s_sg.name]  # ← CAMBIADO

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-master.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = count.index + 1
  })
}

resource "openstack_compute_instance_v2" "k3s_worker" {
  count           = var.worker_count
  name            = "${var.cluster_name}-worker-${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.flavor_worker
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k3s_sg.name]  # ← CAMBIADO

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-worker.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = count.index + 1
  })
}

