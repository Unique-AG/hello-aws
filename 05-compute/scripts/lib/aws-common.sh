#!/usr/bin/env bash
#######################################
# Shared helpers for the pod VM scripts
#######################################
# Sourced, not executed. Extracted because the same guards drifted apart across
# the sibling scripts: an argument check, a version check and a describe-failure
# check each existed in one copy and not the other.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

# Without this a flag given no value dies on $2 with a raw unbound-variable
# message. Call as: need_value "$@"
need_value() {
  [[ $# -ge 2 && -n "${2:-}" ]] || error "$1 needs a value (try --help)"
}

require_positive_int() {
  [[ "$2" =~ ^[1-9][0-9]*$ ]] || error "$1 must be a positive whole number, got '$2'"
}

# Prints the comment header as help, so the two never drift.
print_help() {
  awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "$1"
}

tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

# An AWS call that fails is not an AWS call that returned nothing: collapsing
# the two makes a throttle look like a missing or misconfigured resource.
# Usage: TSV=$(describe_or_die "what this reads" aws ec2 describe-... )
describe_or_die() {
  local what="$1"; shift
  local out
  if ! out=$("$@" 2>&1); then
    error "Cannot read ${what}: ${out}"
  fi
  printf '%s' "$out"
}

# Region, account and key for one environment, with the guards both scripts
# need: the layers can be init'd for different environments, and a key from the
# wrong region is rejected by every API that takes one.
# Sets TARGET_REGION, KMS_KEY_ARN, CALLER_ACCOUNT.
resolve_deployment_target() {
  local tf_compute="$1" tf_infra="$2" env_name="$3"

  CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

  local compute_account compute_region infra_account infra_region
  compute_account=$(tf_out "$tf_compute" aws_account_id)
  compute_region=$(tf_out "$tf_compute" aws_region)
  infra_account=$(tf_out "$tf_infra" aws_account_id)
  infra_region=$(tf_out "$tf_infra" aws_region)

  if [[ -z "$compute_region" || -z "$infra_region" ]]; then
    [[ -n "${TARGET_REGION:-}" && -n "${KMS_KEY_ARN:-}" ]] || error \
      "Cannot read terraform state${env_name:+ for $env_name}. Run terraform init for 05-compute and 03-infrastructure, or pass both --region and --kms-key-arn."
    warn "No terraform state — cannot confirm ${CALLER_ACCOUNT} is the${env_name:+ $env_name} account"
  else
    [[ "$compute_account" == "$infra_account" && "$compute_region" == "$infra_region" ]] || error \
      "05-compute state is ${compute_account}/${compute_region} but 03-infrastructure is ${infra_account}/${infra_region}. Re-init both for the same environment."
    [[ "$compute_account" == "$CALLER_ACCOUNT" ]] || error \
      "Credentials are for ${CALLER_ACCOUNT}, but this deployment is ${compute_account}"
    TARGET_REGION="${TARGET_REGION:-$compute_region}"
  fi

  if [[ -z "${TARGET_REGION:-}" ]]; then
    TARGET_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
  fi
  [[ -n "${TARGET_REGION:-}" ]] || error "Could not determine the target region; pass --region"

  if [[ -z "${KMS_KEY_ARN:-}" ]]; then
    KMS_KEY_ARN=$(tf_out "$tf_infra" kms_key_general_arn)
    [[ -n "$KMS_KEY_ARN" ]] || error "Could not resolve the general KMS key; pass --kms-key-arn"
  fi

  local key_region
  key_region="$(cut -d: -f4 <<<"$KMS_KEY_ARN")"
  [[ "$key_region" == "$TARGET_REGION" ]] \
    || error "KMS key is in ${key_region} but the target region is ${TARGET_REGION}"
}
