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
# SOLO 1 MASTER MÍNIMO - 0 REGLAS NUEVAS
# ========================================
resource "openstack_compute_instance_v2" "k3s_master" {
  count           = 1
  name            = "${var.cluster_name}-master-1"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = "S1-2"  # ← MÁS PEQUEÑO: 1 core, 2GB
  key_pair        = var.ssh_keypair_name  # ← Usa keypair EXISTENTE
  security_groups = ["default"]

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-master.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = 1
  })
}
