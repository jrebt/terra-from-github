output "master_public_ips" {
  description = "Public IPs of master nodes"
  value       = openstack_compute_instance_v2.k3s_master[*].access_ip_v4
}

output "worker_public_ips" {
  description = "Public IPs of worker nodes"
  value       = openstack_compute_instance_v2.k3s_worker[*].access_ip_v4
}

output "k3s_api_endpoint" {
  description = "K3s API endpoint"
  value       = length(openstack_compute_instance_v2.k3s_master) > 0 ? "https://${openstack_compute_instance_v2.k3s_master[0].access_ip_v4}:6443" : ""
}

output "ansible_inventory" {
  description = "Ansible inventory in YAML format"
  value = templatefile("${path.module}/templates/inventory.tpl", {
    master_ips = zipmap(
      openstack_compute_instance_v2.k3s_master[*].name,
      openstack_compute_instance_v2.k3s_master[*].access_ip_v4
    )
    worker_ips = zipmap(
      openstack_compute_instance_v2.k3s_worker[*].name,
      openstack_compute_instance_v2.k3s_worker[*].access_ip_v4
    )
  })
}
