#!/usr/bin/env bash
#######################################
# Restore Scheduled Secrets
#######################################
# Restores any AWS Secrets Manager secrets that are scheduled for deletion.
# This allows Terraform to reuse existing secrets instead of creating new ones
# after an overnight teardown/recreate cycle.
#
# Usage:
#   ./scripts/restore-scheduled-secrets.sh
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

# Check AWS CLI
if ! command -v aws &> /dev/null; then
  error "AWS CLI not found"
  exit 1
fi

# Get AWS region from environment or use default
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-2}}"

info "Checking for secrets scheduled for deletion in region: ${AWS_REGION}"

# Get list of secrets scheduled for deletion
SCHEDULED_SECRETS=$(aws secretsmanager list-secrets \
  --region "${AWS_REGION}" \
  --filters Key=deletion-date,Values=* \
  --query "SecretList[?DeletionDate!=null].{Name:Name,ARN:ARN,DeletionDate:DeletionDate}" \
  --output json 2>/dev/null || echo "[]")

if [ "$SCHEDULED_SECRETS" = "[]" ] || [ -z "$SCHEDULED_SECRETS" ]; then
  log "No secrets scheduled for deletion"
  exit 0
fi

# Count secrets
SECRET_COUNT=$(echo "$SCHEDULED_SECRETS" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$SECRET_COUNT" -eq 0 ]; then
  log "No secrets scheduled for deletion"
  exit 0
fi

info "Found ${SECRET_COUNT} secret(s) scheduled for deletion"

# Restore each scheduled secret
RESTORED=0
FAILED=0

while IFS='|' read -r arn name _deletion_date; do
  if [ -z "$arn" ] || [ "$arn" = "null" ]; then
    continue
  fi

  info "Restoring secret: ${name}"

  if aws secretsmanager restore-secret \
    --region "${AWS_REGION}" \
    --secret-id "$arn" \
    --output json > /dev/null 2>&1; then
    log "Successfully restored: ${name}"
    RESTORED=$((RESTORED + 1))
  else
    warn "Failed to restore: ${name}"
    FAILED=$((FAILED + 1))
  fi
done < <(echo "$SCHEDULED_SECRETS" | jq -r '.[] | "\(.ARN)|\(.Name)|\(.DeletionDate)"')

if [ "$RESTORED" -gt 0 ]; then
  log "Restored ${RESTORED} secret(s)"
fi

if [ "$FAILED" -gt 0 ]; then
  warn "${FAILED} secret(s) could not be restored (may already be deleted)"
fi

exit 0
