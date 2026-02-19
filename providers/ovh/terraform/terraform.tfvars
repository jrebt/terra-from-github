# Copia este archivo a terraform.tfvars y rellena los valores

region                  = "GRA11"
cluster_name            = "k3s-prod"
master_count            = 1
worker_count            = 0
flavor_master           = "b2-7"
image_name              = "Ubuntu 22.04"
# ssh_public_key and service_name come from GitHub Secrets (TF_VAR_ssh_public_key, TF_VAR_service_name)
