#!/usr/bin/env bash
#######################################
# Cancel Pending KMS Key Deletions
#######################################
# Cancels any AWS KMS keys that are in "PendingDeletion" state.
# This allows Terraform to reuse existing KMS keys instead of creating new ones
# after an overnight teardown/recreate cycle.
#
# Usage:
#   ./scripts/cancel-pending-kms-deletions.sh
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

# Check jq
if ! command -v jq &> /dev/null; then
  error "jq is required. Install with: brew install jq"
  exit 1
fi

# Get AWS region from environment or use default
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-central-2}}"

info "Checking for KMS keys pending deletion in region: ${AWS_REGION}"

# Get list of KMS keys pending deletion
PENDING_KEYS=$(aws kms list-keys \
  --region "${AWS_REGION}" \
  --output json 2>/dev/null | jq -r '.Keys[] | .KeyId' || echo "")

if [ -z "$PENDING_KEYS" ]; then
  log "No KMS keys found"
  exit 0
fi

# Check each key for pending deletion status
CANCELLED=0
FAILED=0
NOT_PENDING=0

for key_id in $PENDING_KEYS; do
  # Get key details
  KEY_INFO=$(aws kms describe-key \
    --region "${AWS_REGION}" \
    --key-id "$key_id" \
    --output json 2>/dev/null || echo "{}")

  KEY_STATE=$(echo "$KEY_INFO" | jq -r '.KeyMetadata.KeyState // "Unknown"' 2>/dev/null || echo "Unknown")
  if [ "$KEY_STATE" != "PendingDeletion" ]; then
    NOT_PENDING=$((NOT_PENDING + 1))
    continue
  fi

  # Get key alias if available
  KEY_ALIAS=$(aws kms list-aliases \
    --region "${AWS_REGION}" \
    --output json 2>/dev/null | \
    jq -r --arg key_id "$key_id" '.Aliases[] | select(.TargetKeyId == $key_id) | .AliasName' 2>/dev/null || echo "")

  DISPLAY_NAME="${KEY_ALIAS:-$key_id}"
  info "Cancelling deletion for key: ${DISPLAY_NAME}"

  if aws kms cancel-key-deletion \
    --region "${AWS_REGION}" \
    --key-id "$key_id" \
    --output json > /dev/null 2>&1; then
    # After cancelling deletion, the key is in Disabled state — re-enable it
    if aws kms enable-key \
      --region "${AWS_REGION}" \
      --key-id "$key_id" \
      --output json > /dev/null 2>&1; then
      log "Successfully cancelled deletion and re-enabled: ${DISPLAY_NAME}"
    else
      warn "Cancelled deletion but failed to re-enable: ${DISPLAY_NAME}"
    fi
    CANCELLED=$((CANCELLED + 1))
  else
    warn "Failed to cancel deletion: ${DISPLAY_NAME}"
    FAILED=$((FAILED + 1))
  fi
done

if [ "$CANCELLED" -gt 0 ]; then
  log "Cancelled deletion for ${CANCELLED} KMS key(s)"
fi

if [ "$NOT_PENDING" -gt 0 ] && [ "$CANCELLED" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
  log "No KMS keys pending deletion (${NOT_PENDING} key(s) checked)"
fi

if [ "$FAILED" -gt 0 ]; then
  warn "${FAILED} key(s) could not be cancelled (may already be deleted or not pending)"
fi

exit 0
