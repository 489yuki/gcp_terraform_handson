terraform {
    required_version = "~> 1.9"

    required_providers {
        google = {
            source = "hashicorp/google"
            version = "~> 6.0"
        }
        google-beta = {
            source = "hashicorp/google-beta"
            version = "~> 6.0"
        }
    }
}

provider "google" {
    project = var.project_id
    region = var.region
}

module "vpc" {
    source = "../../modules/vpc"
    project_id = var.project_id
    name = var.vpc_name
    subnets = var.subnets
    labels = var.labels
}