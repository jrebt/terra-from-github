#cloud-config
ssh_authorized_keys:
  - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - git
  - ufw

runcmd:
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow from 10.0.0.0/24 to any port 22 proto tcp
  - ufw allow from 10.0.0.0/24 to any port 6443 proto tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow from 10.0.0.0/24
  - ufw --force enable
  - echo "Master node ${node_index} initialized" > /var/log/cloud-init-done.log
