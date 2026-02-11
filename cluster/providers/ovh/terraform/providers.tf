provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "openstack" {
  auth_url    = "https://auth.cloud.ovh.net/v3"
  domain_name = "default"
  tenant_id   = var.openstack_tenant_id
  user_name   = var.openstack_username
  password    = var.openstack_password
  region      = var.region
  insecure    = true
}
