output "ansible_inventory" {
  value = yamlencode({
    all = {
      children = {
        k3s_masters = {
          hosts = {
            for idx, master in openstack_compute_instance_v2.k3s_master :
            master.name => {
              ansible_host = master.access_ip_v4
              ansible_user = "ubuntu"
            }
          }
        }
        k3s_workers = {
          hosts = {
            for idx, worker in openstack_compute_instance_v2.k3s_worker :
            worker.name => {
              ansible_host = worker.access_ip_v4
              ansible_user = "ubuntu"
            }
          }
        }
      }
    }
  })
}
