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

resource "aws_servicequotas_service_quota" "home" {
  for_each = local.quota_requests

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
  value        = each.value.value
}

# The same values in the Region this installation recovers into, so a failover
# does not land in an account that cannot hold the workload.
resource "aws_servicequotas_service_quota" "recovery" {
  for_each = local.quota_recovery_region == null ? {} : local.quota_requests
  provider = aws.recovery

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
  value        = each.value.value
}

output "quota_list_keys" {
  description = "Adjustable quotas this layer requests, for the layers that check them and the capacity review"
  value       = sort(keys(local.quota_requests))
}

output "quota_recovery_region" {
  description = "Region the quota requests are mirrored into, null where the installation is single-Region"
  value       = local.quota_recovery_region
}
