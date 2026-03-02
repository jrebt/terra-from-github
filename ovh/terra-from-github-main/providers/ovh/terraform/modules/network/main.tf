# Red privada, subnet y router para salida a internet

data "openstack_networking_network_v2" "ext_net" {
  name = "Ext-Net"
}

resource "openstack_networking_network_v2" "private" {
  name           = "${var.cluster_name}-private"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "private" {
  name            = "${var.cluster_name}-subnet"
  network_id      = openstack_networking_network_v2.private.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = ["213.186.33.99", "8.8.8.8"]
  allocation_pool {
    start = cidrhost(var.subnet_cidr, 10)
    end   = cidrhost(var.subnet_cidr, 200)
  }
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.cluster_name}-router"
  external_network_id = data.openstack_networking_network_v2.ext_net.id
  admin_state_up      = true
}

resource "openstack_networking_router_interface_v2" "router_iface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.private.id
}
