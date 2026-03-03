#cloud-config
ssh_authorized_keys:
  - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - curl
  - ufw

runcmd:
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw --force enable
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${tailscale_auth_key} --hostname=k3s-prod-bastion --accept-routes --ssh
  - echo "Bastion initialized with Tailscale" > /var/log/cloud-init-done.log
