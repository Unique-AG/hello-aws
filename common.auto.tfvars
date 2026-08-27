#######################################
# Common Configuration - Shared Across All Layers
#######################################
#
# This file contains common configuration values used across all layers.
# It should be included in each layer's terraform command or referenced
# via symlink/copy in each layer's environments directory.
#
# Usage:
#   terraform plan -var-file=../../common.auto.tfvars -var-file=environments/dev/00-config.auto.tfvars
#######################################

# AWS Configuration (common across all layers)
aws_region     = "eu-central-2"
aws_account_id = null # Will be auto-detected, set explicitly for deterministic naming in CI/CD

# Organization configuration (common across all layers)
org         = "unique"
org_moniker = "uq"

# Product identifiers
product         = "dogfood"
product_moniker = "dogfood"

# Governance tracking (set by CI/CD, common across all layers)
semantic_version = "0.1.0" # Set by CI/CD (e.g., "0.1.0")

# Azure Container Registry (common across all layers that use ECR pull-through cache)
acr_registry_url = "uniquecr.azurecr.io"
