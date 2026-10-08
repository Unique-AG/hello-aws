#!/usr/bin/env bash
#######################################
# Conduct Pod VM AMI Copy Script
#######################################
#
# Copies a Confidential Containers pod VM AMI into this deployment's region,
# re-encrypted under the general KMS key, and prints the resulting AMI ID for
# instance-config.yaml.
#
# The pinned upstream image is a DEBUG image published for proofs of concept,
# from an AWS account with no verifiable link to the project. Read the pod VM
# image section of 05-compute/README.md before using it for anything but sbx;
# build-podvm-image.sh is the path for anything else.
#
# Usage:
#   ./copy-podvm-ami.sh <env> [options]
#
# Options:
#   -s, --source-ami ID      Source AMI (default: the pinned v0.22.0 image)
#       --source-region R    Region to copy from (default: us-east-2)
#   -r, --region REGION      Target region (default: from terraform state)
#   -k, --kms-key-arn ARN    Key for the copy (default: from terraform state)
#   -n, --name NAME          Name for the copy (default: the source's name)
#       --no-wait            Return once the copy is started, without polling
#       --wait-minutes N     How long to poll for the copy (default: 45)
#       --verify-only        Check the source image and exit without copying
#   -h, --help               Show this help message
#
# Examples:
#   # Copy the pinned image into the sbx deployment
#   ./copy-podvm-ami.sh sbx
#
#   # Check the upstream image without reading any terraform state
#   ./copy-podvm-ami.sh --verify-only
#######################################

set -euo pipefail

# shellcheck source=05-compute/scripts/lib/aws-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/aws-common.sh"

#######################################
# Defaults
#######################################

# Pinned to the CAA version the peerpods chart vendors (appVersion v0.22.0).
# Bumping the chart means re-pinning this, and re-checking the fingerprint below.
DEFAULT_SOURCE_AMI="ami-0edeef8b3d8ff0444"
DEFAULT_SOURCE_REGION="us-east-2"
EXPECTED_NAME="podvm-ubuntu-amd64-0-22-0"
EXPECTED_OWNER="992382582441"

ENV_NAME=""
SOURCE_AMI=""
SOURCE_REGION="$DEFAULT_SOURCE_REGION"
TARGET_REGION=""
KMS_KEY_ARN=""
AMI_NAME=""
WAIT=true
WAIT_MINUTES=45
VERIFY_ONLY=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_COMPUTE="${REPO_ROOT}/05-compute/terraform"
TF_INFRA="${REPO_ROOT}/03-infrastructure/terraform"

#######################################
# Arguments
#######################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source-ami)   need_value "$@"; SOURCE_AMI="$2"; shift 2 ;;
    --source-region)   need_value "$@"; SOURCE_REGION="$2"; shift 2 ;;
    -r|--region)       need_value "$@"; TARGET_REGION="$2"; shift 2 ;;
    -k|--kms-key-arn)  need_value "$@"; KMS_KEY_ARN="$2"; shift 2 ;;
    -n|--name)         need_value "$@"; AMI_NAME="$2"; shift 2 ;;
    --wait-minutes)    need_value "$@"; WAIT_MINUTES="$2"; shift 2 ;;
    --no-wait)         WAIT=false; shift ;;
    --verify-only)     VERIFY_ONLY=true; shift ;;
    -h|--help)         print_help "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)                error "Unknown option: $1 (try --help)" ;;
    *)
      [[ -z "$ENV_NAME" ]] || error "Unexpected argument: $1 (try --help)"
      ENV_NAME="$1"; shift ;;
  esac
done

SOURCE_AMI="${SOURCE_AMI:-$DEFAULT_SOURCE_AMI}"

[[ "$WAIT_MINUTES" =~ ^[1-9][0-9]*$ ]] \
  || error "--wait-minutes must be a positive whole number, got '${WAIT_MINUTES}'"

#######################################
# Pre-checks
#######################################

command -v aws >/dev/null 2>&1 || error "aws CLI is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || error "aws CLI has no usable credentials"


if [[ "$VERIFY_ONLY" == false ]]; then
  [[ -n "$ENV_NAME" ]] || error "No environment given. Usage: $(basename "$0") <env> (try --help)"
  [[ -d "${TF_COMPUTE}/environments/${ENV_NAME}" ]] \
    || error "No such environment: ${ENV_NAME} (looked in 05-compute/terraform/environments)"

  CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

  # Each layer is init'd per environment, so their states can be for different
  # ones. Mixing them copies to one environment's region under another's key.
  COMPUTE_ACCOUNT=$(tf_out "$TF_COMPUTE" aws_account_id)
  COMPUTE_REGION=$(tf_out "$TF_COMPUTE" aws_region)
  INFRA_ACCOUNT=$(tf_out "$TF_INFRA" aws_account_id)
  INFRA_REGION=$(tf_out "$TF_INFRA" aws_region)

  if [[ -z "$COMPUTE_REGION" || -z "$INFRA_REGION" ]]; then
    # Nothing to resolve against and nothing to guard, so require both rather
    # than guess a region and land the copy where the adaptor cannot see it.
    [[ -n "$TARGET_REGION" && -n "$KMS_KEY_ARN" ]] || error \
      "Cannot read terraform state for ${ENV_NAME}. Run terraform init for 05-compute and 03-infrastructure, or pass both --region and --kms-key-arn."
    warn "No terraform state — cannot confirm ${CALLER_ACCOUNT} is the ${ENV_NAME} account"
  else
    [[ "$COMPUTE_ACCOUNT" == "$INFRA_ACCOUNT" && "$COMPUTE_REGION" == "$INFRA_REGION" ]] || error \
      "05-compute state is ${COMPUTE_ACCOUNT}/${COMPUTE_REGION} but 03-infrastructure is ${INFRA_ACCOUNT}/${INFRA_REGION}. Re-init both for ${ENV_NAME}."
    [[ "$COMPUTE_ACCOUNT" == "$CALLER_ACCOUNT" ]] || error \
      "Credentials are for ${CALLER_ACCOUNT}, but ${ENV_NAME} is ${COMPUTE_ACCOUNT}"
    TARGET_REGION="${TARGET_REGION:-$COMPUTE_REGION}"
    info "Account ${CALLER_ACCOUNT}, environment ${ENV_NAME}"
  fi

  if [[ -z "$TARGET_REGION" ]]; then
    TARGET_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
  fi
  [[ -n "$TARGET_REGION" ]] || error "Could not determine the target region; pass --region"

  if [[ -z "$KMS_KEY_ARN" ]]; then
    KMS_KEY_ARN=$(tf_out "$TF_INFRA" kms_key_general_arn)
    [[ -n "$KMS_KEY_ARN" ]] || error "Could not resolve the general KMS key; pass --kms-key-arn"
  fi

  # A KMS key is regional; copy-image rejects one from another region.
  KEY_REGION="$(cut -d: -f4 <<<"$KMS_KEY_ARN")"
  [[ "$KEY_REGION" == "$TARGET_REGION" ]] \
    || error "KMS key is in ${KEY_REGION} but the copy targets ${TARGET_REGION}"
  info "Target ${TARGET_REGION}, encrypting under ${KMS_KEY_ARN}"
fi

#######################################
# Verify the source before copying it
#######################################

info "Inspecting ${SOURCE_AMI} in ${SOURCE_REGION}"

# Tab-separated: AMI names may contain spaces, which a space-split would shift
# across the following fields.
if ! SOURCE_TSV=$(aws ec2 describe-images --region "$SOURCE_REGION" --image-ids "$SOURCE_AMI" \
  --query 'Images[0].[Name,OwnerId,State,Architecture,BootMode,TpmSupport]' \
  --output text 2>&1); then
  error "Cannot read ${SOURCE_AMI} in ${SOURCE_REGION}: ${SOURCE_TSV}"
fi

IFS=$'\t' read -r SRC_NAME SRC_OWNER SRC_STATE SRC_ARCH SRC_BOOT SRC_TPM <<<"$SOURCE_TSV"

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
  PROVENANCE="upstream-debug-image-unverified-publisher"
  DESCRIPTION="Conduct sandbox pod VM (upstream CoCo debug image, copied)"
else
  # Name and owner are only known for the pinned image, so they go unchecked
  # here and the tags must not imply otherwise.
  warn "Not the pinned image — verify its provenance yourself"
  PROVENANCE="copied-from-${SRC_OWNER}"
  DESCRIPTION="Conduct sandbox pod VM (copied from ${SOURCE_AMI} in ${SOURCE_REGION})"
fi

# Resolve first, so --name can stand in for a source with no name of its own.
if [[ -z "$AMI_NAME" ]]; then
  [[ -n "$SRC_NAME" && "$SRC_NAME" != "None" ]] || error "Source AMI has no name; pass --name"
  AMI_NAME="$SRC_NAME"
fi

if [[ "$VERIFY_ONLY" == true ]]; then
  log "Verify only — nothing copied"
  exit 0
fi

#######################################
# Copy
#######################################

# describe-images returns pending and failed copies too, and a failed one keeps
# the name -- so branch on state rather than on the ID existing. A failed call
# is distinguished from an absent image, since only one of them means "copy".
if ! EXISTING_TSV=$(aws ec2 describe-images --region "$TARGET_REGION" --owners self \
  --filters "Name=name,Values=${AMI_NAME}" \
  --query 'Images[0].[ImageId,State]' --output text 2>&1); then
  error "Cannot list images in ${TARGET_REGION}: ${EXISTING_TSV}"
fi
IFS=$'\t' read -r EXISTING EXISTING_STATE <<<"$EXISTING_TSV"

AMI_ID=""
STARTED_COPY=false

case "$EXISTING_STATE" in
  available)
    log "Already present in ${TARGET_REGION}: ${BOLD}${EXISTING}${NC}"
    AMI_ID="$EXISTING"

    # A copy made under a different key still carries the right name, and an
    # unencrypted one is what this script exists to avoid -- so refuse it
    # rather than print it as the AMI to configure.
    EXISTING_KEY=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$EXISTING" \
      --query 'Images[0].BlockDeviceMappings[?Ebs].Ebs.KmsKeyId | [0]' \
      --output text 2>/dev/null || echo "None")
    if [[ "$EXISTING_KEY" == "None" || -z "$EXISTING_KEY" ]]; then
      error "${EXISTING} is not encrypted. Deregister it and run again."
    elif [[ "$EXISTING_KEY" != "$KMS_KEY_ARN" ]]; then
      error "${EXISTING} is encrypted under ${EXISTING_KEY}, not ${KMS_KEY_ARN}. Deregister it and run again."
    fi
    ;;
  pending)
    info "A copy named ${AMI_NAME} is still pending: ${EXISTING}"
    AMI_ID="$EXISTING"
    ;;
  None|"")
    ;;
  *)
    error "An image named ${AMI_NAME} exists in state ${EXISTING_STATE} (${EXISTING}). Deregister it, then run again."
    ;;
esac

if [[ -z "$AMI_ID" ]]; then
  info "Copying to ${TARGET_REGION}"
  AMI_ID=$(aws ec2 copy-image \
    --region "$TARGET_REGION" \
    --source-region "$SOURCE_REGION" \
    --source-image-id "$SOURCE_AMI" \
    --name "$AMI_NAME" \
    --description "$DESCRIPTION" \
    --encrypted --kms-key-id "$KMS_KEY_ARN" \
    --query 'ImageId' --output text) || error "copy-image failed"
  STARTED_COPY=true
  log "Copy started: ${BOLD}${AMI_ID}${NC}"
fi

# Unconditional: a re-run after an interrupted copy must still get tagged.
aws ec2 create-tags --region "$TARGET_REGION" --resources "$AMI_ID" --tags \
  "Key=Name,Value=${AMI_NAME}" \
  "Key=SourceImageId,Value=${SOURCE_AMI}" \
  "Key=SourceRegion,Value=${SOURCE_REGION}" \
  "Key=SourceOwner,Value=${SRC_OWNER}" \
  "Key=Provenance,Value=${PROVENANCE}" >/dev/null || warn "Could not tag ${AMI_ID}"

#######################################
# Wait
#######################################

# Not `aws ec2 wait image-available`: its fixed 40x15s gives up after ten
# minutes, and a cross-region encrypted copy can take longer than that.
if [[ "$WAIT" == true ]]; then
  STATE=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
    --query 'Images[0].State' --output text 2>/dev/null || echo "unknown")

  if [[ "$STATE" != "available" ]]; then
    info "Waiting for ${AMI_ID} (up to ${WAIT_MINUTES} minutes)"
    DEADLINE=$(( $(date +%s) + WAIT_MINUTES * 60 ))
    # A throttled or dropped describe-images must not be read as a failed copy.
    UNREADABLE=0

    while true; do
      case "$STATE" in
        available)
          break
          ;;
        pending)
          UNREADABLE=0
          ;;
        unknown)
          UNREADABLE=$(( UNREADABLE + 1 ))
          (( UNREADABLE <= 5 )) || error "Cannot read ${AMI_ID} after 5 attempts; check it in the console"
          warn "describe-images failed (${UNREADABLE}/5), retrying"
          ;;
        *)
          REASON=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
            --query 'Images[0].StateReason.Message' --output text 2>/dev/null || echo "no reason given")
          error "Copy ended in state ${STATE}: ${REASON}"
          ;;
      esac

      if (( $(date +%s) >= DEADLINE )); then
        error "Still pending after ${WAIT_MINUTES} minutes. It may yet finish — re-run to pick it up, or check ${AMI_ID} in the console."
      fi
      sleep 20
      STATE=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
        --query 'Images[0].State' --output text 2>/dev/null || echo "unknown")
    done
  fi
  log "Available"

  # The copy creates its own snapshot, billed and listed separately, and it
  # outlives the AMI if the image is ever deregistered.
  SNAPSHOT_ID=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
    --query 'Images[0].BlockDeviceMappings[?Ebs].Ebs.SnapshotId | [0]' --output text 2>/dev/null || echo "None")
  if [[ -n "$SNAPSHOT_ID" && "$SNAPSHOT_ID" != "None" ]]; then
    aws ec2 create-tags --region "$TARGET_REGION" --resources "$SNAPSHOT_ID" --tags \
      "Key=Name,Value=${AMI_NAME}" \
      "Key=SourceImageId,Value=${SOURCE_AMI}" \
      "Key=Provenance,Value=${PROVENANCE}" >/dev/null 2>&1 \
      || warn "Could not tag snapshot ${SNAPSHOT_ID}"
  fi
fi

#######################################
# Next steps
#######################################

echo ""
echo -e "${BOLD}Pod VM AMI:${NC} ${AMI_ID}  (${TARGET_REGION})"

if [[ "$WAIT" == false ]]; then
  # Whether this run started the copy or found one already pending, the AMI is
  # not usable and its snapshot is untagged.
  FINAL_STATE=$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
    --query 'Images[0].State' --output text 2>/dev/null || echo "unknown")
  if [[ "$FINAL_STATE" != "available" ]]; then
    echo ""
    warn "State is ${FINAL_STATE} — not usable yet, and the snapshot is untagged."
    warn "Re-run without --no-wait to follow it and finish tagging."
    exit 0
  fi
fi

echo ""
echo "Set it in 06-applications/${ENV_NAME}/instance-config.yaml:"
echo ""
echo "    aws:"
echo "      sandbox:"
echo "        podvmAmiId: ${AMI_ID}"
echo ""
echo "then re-run the configure step:"
echo ""
echo "    cd 06-applications && ./scripts/configure-instance.sh ${ENV_NAME}"
echo ""
if [[ "$SOURCE_AMI" == "$DEFAULT_SOURCE_AMI" ]]; then
  warn "This is upstream's debug image from an unverified publisher. Suitable for"
  warn "sbx only — build a trusted image before the sandbox runs anything real."
fi
