# terraform/backend.tf
terraform {
  required_version = ">= 1.7.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  
#  backend "gcs" {
#    bucket = "mi-proyecto-terraform-tfstate"  # Cambia por tu bucket
#    prefix = "terraform/state"
#  }
}
