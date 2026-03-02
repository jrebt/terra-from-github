# K3s master: solo red privada + floating IP para trafico web

resource "openstack_compute_instance_v2" "master" {
  name            = "${var.cluster_name}-master-1"
  image_id        = var.image_id
  flavor_name     = var.flavor
  key_pair        = var.keypair_name
  security_groups = [var.secgroup_name]

  # Solo red privada - sin acceso publico directo
  network {
    uuid        = var.private_network_id
    fixed_ip_v4 = var.master_private_ip
  }

  user_data = templatefile("${path.module}/cloud-init-master.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = 1
  })
}

# Floating IP para trafico web (Kong 80/443)
resource "openstack_networking_floatingip_v2" "k3s_web" {
  pool = "Ext-Net"
}

resource "openstack_compute_floatingip_associate_v2" "k3s_web" {
  floating_ip = openstack_networking_floatingip_v2.k3s_web.address
  instance_id = openstack_compute_instance_v2.master.id
}
