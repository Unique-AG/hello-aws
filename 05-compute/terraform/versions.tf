terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.0"
    }
  }
}

