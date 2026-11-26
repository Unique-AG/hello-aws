# Service quota requests (CA 16.4, AWS-RES-11).
#
# The list is quota-list.yaml beside this layer; the recovery Region comes from
# the pairing table (CA 16.3), so the two never disagree.

locals {
  quota_list = yamldecode(file("${path.module}/../quota-list.yaml"))

  quota_recovery_region = try(
    yamldecode(file("${path.module}/../../recovery-pairing.yaml")).pairs[var.aws_region],
    null
  )

  quota_rules_per_sg = one([for q in local.quota_list.quotas : q.values if q.key == "vpc_rules_per_sg"])
  quota_sgs_per_eni  = one([for q in local.quota_list.quotas : q.values if q.key == "vpc_sgs_per_eni"])

  # Only the adjustable ones are requested; Service Quotas refuses the rest.
  quota_requests = {
    for q in local.quota_list.quotas :
    q.key => {
      service_code = q.service_code
      quota_code   = q.quota_code
      value        = q.values[var.installation_size]
    }
  }
}

# A request below the value already applied is refused, and the applied value
# can differ per Region, so each target is the larger of the two.
data "aws_servicequotas_service_quota" "home" {
  for_each = local.quota_requests

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
}

resource "aws_servicequotas_service_quota" "home" {
  for_each = local.quota_requests

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
  value        = max(each.value.value, data.aws_servicequotas_service_quota.home[each.key].value)
}

# The same values in the Region this installation recovers into, so a failover
# does not land in an account that cannot hold the workload.
data "aws_servicequotas_service_quota" "recovery" {
  for_each = local.quota_recovery_region == null ? {} : local.quota_requests
  provider = aws.recovery

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
}

resource "aws_servicequotas_service_quota" "recovery" {
  for_each = local.quota_recovery_region == null ? {} : local.quota_requests
  provider = aws.recovery

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
  value        = max(each.value.value, data.aws_servicequotas_service_quota.recovery[each.key].value)
}

output "quota_list_keys" {
  description = "Adjustable quotas this layer requests, for the layers that check them and the capacity review"
  value       = sort(keys(local.quota_requests))

  precondition {
    # AWS refuses a combination above 1,000. A precondition fails the plan;
    # a check block would only warn and the apply would fail instead.
    condition = alltrue([
      for size in local.quota_list.sizes :
      local.quota_rules_per_sg[size] * local.quota_sgs_per_eni[size] <= 1000
    ])
    error_message = "rules per security group x security groups per interface must not exceed 1000 for any size in quota-list.yaml."
  }

  precondition {
    # The catalogue above is not what is requested: each target is the larger of
    # the list value and the value already applied, so a Region sitting higher
    # can carry the product past 1,000 while the catalogue still passes.
    condition = (aws_servicequotas_service_quota.home["vpc_rules_per_sg"].value
    * aws_servicequotas_service_quota.home["vpc_sgs_per_eni"].value) <= 1000
    error_message = "The values requested in this Region multiply above 1000: AWS refuses that combination."
  }

  precondition {
    condition = local.quota_recovery_region == null ? true : (
      aws_servicequotas_service_quota.recovery["vpc_rules_per_sg"].value
      * aws_servicequotas_service_quota.recovery["vpc_sgs_per_eni"].value
    ) <= 1000
    error_message = "The values requested in the recovery Region multiply above 1000: AWS refuses that combination."
  }
}

output "quota_recovery_region" {
  description = "Region the quota requests are mirrored into, null where the installation is single-Region"
  value       = local.quota_recovery_region
}
