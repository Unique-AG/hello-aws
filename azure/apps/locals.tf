locals {
  region_short = {
    "switzerlandnorth" = "chn"
    "switzerlandwest"  = "chw"
    "westeurope"       = "weu"
    "northeurope"      = "neu"
    "swedencentral"    = "sec"
  }

  name_prefix = "${var.org}-${var.product}-${var.environment}"
  name_suffix = lookup(local.region_short, var.location, var.location)

  tags = {
    "org:Name"             = var.org
    "product:Id"           = var.product
    "product:Environment"  = var.environment
    "automation:ManagedBy" = "terraform"
    "automation:Pipeline"  = "github-actions"
  }
}
