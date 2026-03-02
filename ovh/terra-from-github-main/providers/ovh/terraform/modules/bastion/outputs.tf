output "public_ip" {
  value = openstack_compute_instance_v2.bastion.access_ip_v4
}

output "private_ip" {
  value = openstack_compute_instance_v2.bastion.network[1].fixed_ip_v4
}

output "name" {
  value = openstack_compute_instance_v2.bastion.name
}
