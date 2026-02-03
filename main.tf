# terraform/main.tf

# Red VPC
resource "google_compute_network" "vpc_network" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
}

# Subred
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Regla de firewall para SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.environment}-allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # ⚠️ Cambiar por tu IP en producción
  target_tags   = ["ssh", "http"]
}

# Instancia de VM (free tier eligible)
resource "google_compute_instance" "vm_instance" {
  name         = "${var.environment}-vm"
  machine_type = "e2-micro"  # Free tier eligible
  zone         = "${var.region}-b"

  tags = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30  # GB - dentro del free tier
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    
    access_config {
      # IP pública efímera
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    echo "<h1>Hola desde Terraform en GCP!</h1>" > /var/www/html/index.html
  EOF
}

