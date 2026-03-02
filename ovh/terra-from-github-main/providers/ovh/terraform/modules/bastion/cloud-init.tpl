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
  - echo "Bastion initialized" > /var/log/cloud-init-done.log
