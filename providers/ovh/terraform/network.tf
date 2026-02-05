# Obtener la red pública de OVH
data "ovh_cloud_project_network_private" "private_network" {
  count      = 0  # No usaremos red privada por ahora
  service_name = var.service_name
}

# Por ahora usaremos la red pública directamente
# OVH Public Cloud no requiere crear VPC manualmente como AWS/GCP
