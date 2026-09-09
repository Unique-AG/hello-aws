#!/usr/bin/env bash
#######################################
# Conduct Pod VM AMI Copy Script
#######################################
#
# Copies the upstream Confidential Containers pod VM AMI into this deployment's
# region, re-encrypted under the general KMS key, and prints the resulting AMI
# ID for instance-config.yaml.
#
# The upstream image is a DEBUG image published for proofs of concept, from an
# AWS account with no verifiable link to the project. Read the pod VM AMI
# section of 05-compute/README.md before using the result for anything but sbx.
#
# Usage:
#   ./copy-podvm-ami.sh [options]
#
# Options:
#   -s, --source-ami ID      Source AMI (default: the pinned v0.22.0 image)
#       --source-region R    Region to copy from (default: us-east-2)
#   -r, --region REGION      Target region (default: from terraform, else eu-central-2)
#   -k, --kms-key-arn ARN    Key for the copy (default: from terraform)
#   -n, --name NAME          Name for the copy (default: derived from the source)
#       --no-wait            Return once the copy is started, without polling
#       --verify-only        Check the source image and exit without copying
#   -h, --help               Show this help message
#
# Examples:
#   # Copy the pinned image using values resolved from terraform state
#   ./copy-podvm-ami.sh
#
#   # Copy a specific image into a specific region
#   ./copy-podvm-ami.sh --source-ami ami-0123456789abcdef0 --region eu-central-2
#######################################

set -euo pipefail

#######################################
# Colors & Output
#######################################

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

#######################################
# Defaults
#######################################

# Pinned to the CAA version the peerpods chart vendors (appVersion v0.22.0).
# Bumping the chart means re-pinning this, and re-checking the fingerprint below.
DEFAULT_SOURCE_AMI="ami-0edeef8b3d8ff0444"
DEFAULT_SOURCE_REGION="us-east-2"
EXPECTED_NAME="podvm-ubuntu-amd64-0-22-0"
EXPECTED_OWNER="992382582441"

SOURCE_AMI=""
SOURCE_REGION="$DEFAULT_SOURCE_REGION"
TARGET_REGION=""
KMS_KEY_ARN=""
AMI_NAME=""
WAIT=true
VERIFY_ONLY=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

#######################################
# Arguments
#######################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source-ami)   SOURCE_AMI="$2"; shift 2 ;;
    --source-region)   SOURCE_REGION="$2"; shift 2 ;;
    -r|--region)       TARGET_REGION="$2"; shift 2 ;;
    -k|--kms-key-arn)  KMS_KEY_ARN="$2"; shift 2 ;;
    -n|--name)         AMI_NAME="$2"; shift 2 ;;
    --no-wait)         WAIT=false; shift ;;
    --verify-only)     VERIFY_ONLY=true; shift ;;
    -h|--help)         sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                 error "Unknown option: $1 (try --help)" ;;
  esac
done

SOURCE_AMI="${SOURCE_AMI:-$DEFAULT_SOURCE_AMI}"

#######################################
# Pre-checks
#######################################

command -v aws >/dev/null 2>&1 || error "aws CLI is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || error "aws CLI has no usable credentials"

CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# An AMI belongs to one account. Copied into the wrong one it is invisible to
# the adaptor, and the failure shows up much later as a launch error.
if [[ "$VERIFY_ONLY" == false ]]; then
  EXPECTED_ACCOUNT=$(terraform -chdir="${REPO_ROOT}/05-compute/terraform" output -raw aws_account_id 2>/dev/null || true)
  if [[ -n "$EXPECTED_ACCOUNT" && "$EXPECTED_ACCOUNT" != "$CALLER_ACCOUNT" ]]; then
    error "Credentials are for ${CALLER_ACCOUNT}, but this deployment is ${EXPECTED_ACCOUNT}"
  fi
  [[ -n "$EXPECTED_ACCOUNT" ]] || warn "No terraform state here — cannot confirm ${CALLER_ACCOUNT} is the deployment account"
  info "Account: ${CALLER_ACCOUNT}"
fi

# Resolve region and key from state so the copy lands where the cluster is.
if [[ "$VERIFY_ONLY" == false && -z "$TARGET_REGION" ]]; then
  TARGET_REGION=$(terraform -chdir="${REPO_ROOT}/05-compute/terraform" output -raw aws_region 2>/dev/null || true)
  TARGET_REGION="${TARGET_REGION:-${AWS_REGION:-eu-central-2}}"
  info "Target region: ${TARGET_REGION} (resolved)"
fi

if [[ "$VERIFY_ONLY" == false && -z "$KMS_KEY_ARN" ]]; then
  KMS_KEY_ARN=$(terraform -chdir="${REPO_ROOT}/03-infrastructure/terraform" output -raw kms_key_general_arn 2>/dev/null || true)
  [[ -n "$KMS_KEY_ARN" ]] || error "Could not resolve the general KMS key from terraform state; pass --kms-key-arn"
  info "Encrypting under: ${KMS_KEY_ARN}"
fi

#######################################
# Verify the source before copying it
#######################################

info "Inspecting ${SOURCE_AMI} in ${SOURCE_REGION}"

SOURCE_JSON=$(aws ec2 describe-images --region "$SOURCE_REGION" --image-ids "$SOURCE_AMI" --output json 2>/dev/null) \
  || error "Cannot read ${SOURCE_AMI} in ${SOURCE_REGION} — wrong ID, wrong region, or no longer public"

read -r SRC_NAME SRC_OWNER SRC_STATE SRC_ARCH SRC_BOOT SRC_TPM <<<"$(python3 -c '
import json, sys
i = json.load(sys.stdin)["Images"][0]
print(i.get("Name", "-"), i.get("OwnerId", "-"), i.get("State", "-"),
      i.get("Architecture", "-"), i.get("BootMode", "-"), i.get("TpmSupport", "-"))
' <<<"$SOURCE_JSON")"

echo "    Name:  ${SRC_NAME}"
echo "    Owner: ${SRC_OWNER}"
echo "    State: ${SRC_STATE}, ${SRC_ARCH}, boot ${SRC_BOOT}, TPM ${SRC_TPM}"

[[ "$SRC_STATE" == "available" ]] || error "Source AMI is ${SRC_STATE}, not available"

# A pod VM must boot UEFI with a TPM; the shape is what the adaptor launches
# against, so a mismatch here means the wrong image, not a cosmetic difference.
[[ "$SRC_ARCH" == "x86_64" ]] || error "Expected x86_64, got ${SRC_ARCH}"
[[ "$SRC_BOOT" == "uefi" ]]   || error "Expected uefi boot mode, got ${SRC_BOOT}"
[[ "$SRC_TPM" == "v2.0" ]]    || error "Expected TPM v2.0 support, got ${SRC_TPM}"

if [[ "$SOURCE_AMI" == "$DEFAULT_SOURCE_AMI" ]]; then
  [[ "$SRC_NAME" == "$EXPECTED_NAME" ]] \
    || error "Pinned AMI is named ${SRC_NAME}, expected ${EXPECTED_NAME} — refusing to copy"
  [[ "$SRC_OWNER" == "$EXPECTED_OWNER" ]] \
    || error "Pinned AMI is owned by ${SRC_OWNER}, expected ${EXPECTED_OWNER} — refusing to copy"
  log "Pinned image matches its recorded name and owner"
else
  warn "Not the pinned image — verify its provenance yourself"
fi

AMI_NAME="${AMI_NAME:-${SRC_NAME}}"

if [[ "$VERIFY_ONLY" == true ]]; then
  log "Verify only — nothing copied"
  exit 0
fi

#######################################
# Copy
#######################################

EXISTING=$(aws ec2 describe-images --region "$TARGET_REGION" --owners self \
  --filters "Name=name,Values=${AMI_NAME}" --query 'Images[0].ImageId' --output text 2>/dev/null || echo "None")

if [[ "$EXISTING" != "None" && -n "$EXISTING" ]]; then
  log "Already present in ${TARGET_REGION}: ${BOLD}${EXISTING}${NC}"
  AMI_ID="$EXISTING"
else
  info "Copying to ${TARGET_REGION}"
  AMI_ID=$(aws ec2 copy-image \
    --region "$TARGET_REGION" \
    --source-region "$SOURCE_REGION" \
    --source-image-id "$SOURCE_AMI" \
    --name "$AMI_NAME" \
    --description "Conduct sandbox pod VM (upstream CoCo debug image, copied)" \
    --encrypted --kms-key-id "$KMS_KEY_ARN" \
    --query 'ImageId' --output text) || error "copy-image failed"
  log "Copy started: ${BOLD}${AMI_ID}${NC}"

  # Record where it came from; the copy itself keeps no link to the source.
  aws ec2 create-tags --region "$TARGET_REGION" --resources "$AMI_ID" --tags \
    "Key=Name,Value=${AMI_NAME}" \
    "Key=SourceImageId,Value=${SOURCE_AMI}" \
    "Key=SourceRegion,Value=${SOURCE_REGION}" \
    "Key=SourceOwner,Value=${SRC_OWNER}" \
    "Key=Provenance,Value=upstream-debug-image-unverified-publisher" >/dev/null || warn "Could not tag ${AMI_ID}"

  if [[ "$WAIT" == true ]]; then
    info "Waiting for the copy to finish (several minutes)"
    aws ec2 wait image-available --region "$TARGET_REGION" --image-ids "$AMI_ID" \
      || error "Copy did not become available; check the console for ${AMI_ID}"
    log "Available"
  fi
fi

#######################################
# Next steps
#######################################

echo ""
echo -e "${BOLD}Pod VM AMI:${NC} ${AMI_ID}  (${TARGET_REGION})"
echo ""
echo "Set it in instance-config.yaml, then re-run the configure step:"
echo ""
echo "    aws:"
echo "      sandbox:"
echo "        podvmAmiId: ${AMI_ID}"
echo ""
echo "    ./06-applications/scripts/configure-instance.sh"
echo ""
warn "This is upstream's debug image from an unverified publisher. Suitable for"
warn "sbx only — build a trusted image before the sandbox runs anything real."
