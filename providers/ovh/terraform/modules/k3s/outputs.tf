output "master_private_ip" {
  value = openstack_compute_instance_v2.master.network[0].fixed_ip_v4
}

output "master_name" {
  value = openstack_compute_instance_v2.master.name
}

output "master_id" {
  value = openstack_compute_instance_v2.master.id
}

output "floating_ip" {
  value = openstack_networking_floatingip_v2.k3s_web.address
}
