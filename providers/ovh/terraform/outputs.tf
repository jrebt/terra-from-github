# Si ya no hay workers, elimina este bloque por completo
# output "worker_public_ips" { ... }

output "master_public_ips" {
  value = openstack_compute_instance_v2.k3s_master[*].access_ip_v4
}

output "ansible_inventory" {
  value = yamlencode({
    all = {
      children = {
        masters = {
          hosts = {
            for idx, inst in openstack_compute_instance_v2.k3s_master :
            inst.name => {
              ansible_host = inst.access_ip_v4
            }
          }
        }
        # workers vacío de momento
        workers = {
          hosts = {}
        }
      }
    }
  })
}
