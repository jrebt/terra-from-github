# Obtener regiones disponibles
data "ovh_cloud_project_regions" "available" {
  service_name = var.service_name
}

# Obtener la imagen de Ubuntu
data "ovh_cloud_project_image" "ubuntu" {
  service_name = var.service_name
  region       = var.region
  name         = var.image_name
}

# SSH Key
resource "ovh_cloud_project_sshkey" "k3s_keypair" {
  service_name = var.service_name
  name         = "${var.cluster_name}-keypair"
  public_key   = var.ssh_public_key
  region       = var.region
}

# Master nodes
resource "ovh_cloud_project_instance" "k3s_master" {
  count        = var.master_count
  service_name = var.service_name
  name         = "${var.cluster_name}-master-${count.index + 1}"
  region       = var.region
  flavor_name  = var.flavor_master
  image_id     = data.ovh_cloud_project_image.ubuntu.id

  ssh_key_public = ovh_cloud_project_sshkey.k3s_keypair.public_key

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - wget
      - git
    runcmd:
      - echo "Master node ${count.index + 1} initialized" > /var/log/cloud-init-done.log
  EOF
}

# Worker nodes
resource "ovh_cloud_project_instance" "k3s_worker" {
  count        = var.worker_count
  service_name = var.service_name
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  region       = var.region
  flavor_name  = var.flavor_worker
  image_id     = data.ovh_cloud_project_image.ubuntu.id

  ssh_key_public = ovh_cloud_project_sshkey.k3s_keypair.public_key

  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - wget
    runcmd:
      - echo "Worker node ${count.index + 1} initialized" > /var/log/cloud-init-done.log
  EOF
}

# Abrir puertos necesarios (Security Group)
resource "ovh_cloud_project_instance_security_group" "k3s_secgroup" {
  service_name = var.service_name
  name         = "${var.cluster_name}-secgroup"
  description  = "Security group for K3s cluster"
  region       = var.region
}

resource "ovh_cloud_project_instance_security_group_rule" "ssh" {
  service_name       = var.service_name
  security_group_id  = ovh_cloud_project_instance_security_group.k3s_secgroup.id
  direction          = "ingress"
  protocol           = "tcp"
  port_range_min     = 22
  port_range_max     = 22
  ip_range           = "0.0.0.0/0"
}

resource "ovh_cloud_project_instance_security_group_rule" "k3s_api" {
  service_name       = var.service_name
  security_group_id  = ovh_cloud_project_instance_security_group.k3s_secgroup.id
  direction          = "ingress"
  protocol           = "tcp"
  port_range_min     = 6443
  port_range_max     = 6443
  ip_range           = "0.0.0.0/0"
}

resource "ovh_cloud_project_instance_security_group_rule" "http" {
  service_name       = var.service_name
  security_group_id  = ovh_cloud_project_instance_security_group.k3s_secgroup.id
  direction          = "ingress"
  protocol           = "tcp"
  port_range_min     = 80
  port_range_max     = 80
  ip_range           = "0.0.0.0/0"
}

resource "ovh_cloud_project_instance_security_group_rule" "https" {
  service_name       = var.service_name
  security_group_id  = ovh_cloud_project_instance_security_group.k3s_secgroup.id
  direction          = "ingress"
  protocol           = "tcp"
  port_range_min     = 443
  port_range_max     = 443
  ip_range           = "0.0.0.0/0"
}
