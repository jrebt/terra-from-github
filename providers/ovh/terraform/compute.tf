data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

data "openstack_networking_network_v2" "public" {
  name = "Ext-Net"
}

data "openstack_networking_secgroup_v2" "default" {
  name = "default"
}

# ========================================
# ABSOLUTAMENTE 0 REGLAS - SOLO 1 INSTANCIA
# SSH y K3s funcionan con "Ingress Any/Any" del default
# ========================================
resource "openstack_compute_keypair_v2" "k3s_keypair" {
  name       = "${var.cluster_name}-keypair"
  public_key = var.ssh_public_key
}

resource "openstack_compute_instance_v2" "k3s_master" {
  count           = 1
  name            = "${var.cluster_name}-master-1"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = "b2-7"  # 1 core, 2GB - MÍNIMO
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = ["default"]

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-master.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = 1
  })
}
