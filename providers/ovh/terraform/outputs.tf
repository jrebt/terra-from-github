output "master_instances" {
  description = "Master node details"
  value = {
    for idx, instance in ovh_cloud_project_instance.k3s_master : 
    instance.name => {
      id         = instance.id
      ip_address = instance.ip_address
      status     = instance.status
    }
  }
}

output "worker_instances" {
  description = "Worker node details"
  value = {
    for idx, instance in ovh_cloud_project_instance.k3s_worker : 
    instance.name => {
      id         = instance.id
      ip_address = instance.ip_address
      status     = instance.status
    }
  }
}

output "master_public_ips" {
  description = "Public IPs of master nodes"
  value       = [for instance in ovh_cloud_project_instance.k3s_master : instance.ip_address]
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = [for instance in ovh_cloud_project_instance.k3s_worker : instance.ip_address]
}

output "k3s_api_endpoint" {
  description = "K3s API endpoint"
  value       = length(ovh_cloud_project_instance.k3s_master) > 0 ? "https://${ovh_cloud_project_instance.k3s_master[0].ip_address}:6443" : ""
}

# Generar inventory de Ansible
output "ansible_inventory" {
  description = "Ansible inventory in YAML format"
  value = templatefile("${path.module}/templates/inventory.tpl", {
    master_ips  = {
      for instance in ovh_cloud_project_instance.k3s_master :
      instance.name => instance.ip_address
    }
    worker_ips = {
      for instance in ovh_cloud_project_instance.k3s_worker :
      instance.name => instance.ip_address
    }
  })
}
