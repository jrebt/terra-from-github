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

resource "openstack_compute_keypair_v2" "k3s_keypair" {
  name       = "${var.cluster_name}-keypair"
  public_key = var.ssh_public_key
}

resource "openstack_compute_instance_v2" "k3s_master" {
  count           = var.master_count
  name            = "${var.cluster_name}-master-${count.index + 1}"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.flavor_master
  key_pair        = openstack_compute_keypair_v2.k3s_keypair.name
  security_groups = ["default"]

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
  security_groups = ["default"]

  network {
    name = data.openstack_networking_network_v2.public.name
  }

  user_data = templatefile("${path.module}/templates/cloud-init-worker.tpl", {
    ssh_public_key = var.ssh_public_key
    node_index     = count.index + 1
  })
}
