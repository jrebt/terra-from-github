provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "openstack" {
  alias        = "ovh"
  user_name    = var.openstack_username
  tenant_id    = var.openstack_tenant_id
  password     = var.openstack_password
  auth_url     = "https://auth.cloud.ovh.eu/v3.0"
  region       = "GRA11"  # ← CAMBIA ESTO POR TU REGIÓN
  domain_name  = "default"
}
