output "private_network_id" {
  value = openstack_networking_network_v2.private.id
}

output "private_subnet_id" {
  value = openstack_networking_subnet_v2.private.id
}

output "ext_net_id" {
  value = data.openstack_networking_network_v2.ext_net.id
}

output "ext_net_name" {
  value = data.openstack_networking_network_v2.ext_net.name
}

output "subnet_cidr" {
  value = var.subnet_cidr
}
