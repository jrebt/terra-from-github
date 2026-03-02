output "bastion_secgroup_id" {
  value = openstack_networking_secgroup_v2.bastion.id
}

output "bastion_secgroup_name" {
  value = openstack_networking_secgroup_v2.bastion.name
}

output "k3s_secgroup_id" {
  value = openstack_networking_secgroup_v2.k3s.id
}

output "k3s_secgroup_name" {
  value = openstack_networking_secgroup_v2.k3s.name
}
