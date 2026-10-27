locals {
  # AWS rejects a budget notification without subscribers, so none are created without contacts.
  budget_notifications = length(var.budget_contact_emails) > 0 ? {
    actual_80      = { threshold = 80, notification_type = "ACTUAL" }
    forecasted_100 = { threshold = 100, notification_type = "FORECASTED" }
  } : {}
}

resource "aws_budgets_budget" "monthly_budget" {
  name         = "budget-${module.naming.id}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_amount)
  limit_unit   = var.budget_currency
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.notification_type
      subscriber_email_addresses = var.budget_contact_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period_start]
  }
}
