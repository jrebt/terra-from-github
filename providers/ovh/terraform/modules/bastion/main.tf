# Bastion: VM pequeña con IP publica + red privada

resource "openstack_compute_instance_v2" "bastion" {
  name            = "${var.cluster_name}-bastion"
  image_id        = var.image_id
  flavor_name     = var.flavor
  key_pair        = var.keypair_name
  security_groups = [var.secgroup_name]

  # Red publica (Ext-Net) para acceso SSH desde internet
  network {
    name = var.ext_net_name
  }

  # Red privada para acceder al cluster
  network {
    uuid = var.private_network_id
  }

  user_data = templatefile("${path.module}/cloud-init.tpl", {
    ssh_public_key     = var.ssh_public_key
    tailscale_auth_key = var.tailscale_auth_key
  })
}
