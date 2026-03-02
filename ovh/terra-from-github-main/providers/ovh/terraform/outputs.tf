output "bastion_public_ip" {
  description = "IP publica del bastion (para SSH)"
  value       = module.bastion.public_ip
}

output "bastion_private_ip" {
  description = "IP privada del bastion"
  value       = module.bastion.private_ip
}

output "k3s_master_private_ip" {
  description = "IP privada del master K3s"
  value       = module.k3s.master_private_ip
}

output "k3s_floating_ip" {
  description = "IP publica (floating) para Kong (HTTP/HTTPS)"
  value       = module.k3s.floating_ip
}

output "ssh_config" {
  description = "Configuracion SSH para acceder al cluster"
  value       = <<-EOT

    # Añadir a ~/.ssh/config:
    Host bastion
      HostName ${module.bastion.public_ip}
      User ubuntu
      IdentityFile ~/.ssh/id_rsa

    Host k3s
      HostName ${module.k3s.master_private_ip}
      User ubuntu
      ProxyJump bastion
      IdentityFile ~/.ssh/id_rsa

    # Uso: ssh k3s
  EOT
}

output "ansible_inventory" {
  description = "Inventario Ansible (acceso via bastion)"
  value = yamlencode({
    all = {
      children = {
        k3s_masters = {
          hosts = {
            (module.k3s.master_name) = {
              ansible_host                = module.k3s.master_private_ip
              ansible_user                = "ubuntu"
              ansible_ssh_common_args     = "-o ProxyJump=ubuntu@${module.bastion.public_ip}"
            }
          }
        }
      }
    }
  })
}
