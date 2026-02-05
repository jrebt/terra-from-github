# Obtener lista de regiones disponibles
data "ovh_cloud_project_regions" "available" {
  service_name = var.service_name
  has_services_up = ["instance"]
}

# Obtener flavors disponibles (tipos de instancia)
data "ovh_cloud_project_capabilities_containerregistry_filter" "registry_capabilities" {
  service_name = var.service_name
  plan_name    = "SMALL"
  region       = var.region
}

# SSH Key para acceder a las instancias
resource "ovh_cloud_project_user_s3_credential" "k3s_keypair" {
  service_name = var.service_name
}

# Master nodes
resource "ovh_cloud_project_instance" "k3s_master" {
  count        = var.master_count
  service_name = var.service_name
  name         = "${var.cluster_name}-master-${count.index + 1}"
  region       = var.region
  flavor_name  = var.flavor_master
  image_name   = var.image_name

  # SSH keys - usar el formato correcto
  ssh_key {
    name       = "${var.cluster_name}-key"
    public_key = var.ssh_public_key
  }

  user_data = base64encode(<<-EOF
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
  )
}

# Worker nodes
resource "ovh_cloud_project_instance" "k3s_worker" {
  count        = var.worker_count
  service_name = var.service_name
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  region       = var.region
  flavor_name  = var.flavor_worker
  image_name   = var.image_name

  ssh_key {
    name       = "${var.cluster_name}-key"
    public_key = var.ssh_public_key
  }

  user_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - wget
    runcmd:
      - echo "Worker node ${count.index + 1} initialized" > /var/log/cloud-init-done.log
  EOF
  )
}
