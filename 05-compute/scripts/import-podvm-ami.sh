#!/usr/bin/env bash
#######################################
# Conduct Pod VM AMI Import Script
#######################################
#
# Imports a pod VM disk image as an AMI: stages it in S3, converts it to an
# encrypted snapshot via VM Import/Export, and registers the image with the
# boot properties the remote hypervisor requires.
#
# Needs the staging bucket and import role, which are off by default:
#   terraform apply -var enable_podvm_image_import=true
# Turn them back off once the AMI exists.
#
# Usage:
#   ./import-podvm-ami.sh --image PATH [options]
#
# Options:
#   -i, --image PATH      Disk image to import (.raw, or .qcow2 to convert)
#   -n, --name NAME       AMI name (default: derived from the image file)
#   -r, --region REGION   Target region (default: from terraform)
#       --keep-staged     Leave the uploaded image in S3
#       --skip-scan       Skip the trivy scan of the registered AMI
#       --wait-minutes N  How long to poll for the snapshot (default: 60)
#   -h, --help            Show this help message
#
# Examples:
#   # Import an image built by build-podvm-image.sh
#   ./import-podvm-ami.sh --image ./podvm-build/podvm-v0.22.0-x86_64.raw
#######################################

set -euo pipefail

# shellcheck source=05-compute/scripts/lib/aws-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/aws-common.sh"

IMAGE=""
AMI_NAME=""
TARGET_REGION=""
KEEP_STAGED=false
SKIP_SCAN=false
WAIT_MINUTES=60

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_COMPUTE="${REPO_ROOT}/05-compute/terraform"
TF_INFRA="${REPO_ROOT}/03-infrastructure/terraform"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image)      need_value "$@"; IMAGE="$2"; shift 2 ;;
    -n|--name)       need_value "$@"; AMI_NAME="$2"; shift 2 ;;
    -r|--region)     need_value "$@"; TARGET_REGION="$2"; shift 2 ;;
    --keep-staged)   KEEP_STAGED=true; shift ;;
    --skip-scan)     SKIP_SCAN=true; shift ;;
    --wait-minutes)  need_value "$@"; WAIT_MINUTES="$2"; shift 2 ;;
    -h|--help)       awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)               error "Unknown option: $1 (try --help)" ;;
  esac
done

#######################################
# Pre-checks
#######################################

require_positive_int "--wait-minutes" "$WAIT_MINUTES"

[[ -n "$IMAGE" ]] || error "No image given (--image PATH, or --help)"
[[ -f "$IMAGE" ]] || error "No such file: ${IMAGE}"

command -v aws >/dev/null 2>&1 || error "aws CLI is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || error "aws CLI has no usable credentials"

CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)


# Run against a freshly registered image and against one a previous run left
# behind: an AMI that exists is not evidence that it is usable.
verify_ami_properties() {
  local ami="$1"
  local boot tpm imds enc key
  local tsv
  tsv=$(describe_or_die "${ami}" aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$ami" \
    --query 'Images[0].[BootMode,TpmSupport,ImdsSupport,Architecture,BlockDeviceMappings[?Ebs].Ebs.Encrypted|[0],BlockDeviceMappings[?Ebs].Ebs.KmsKeyId|[0]]' \
    --output text)
  local arch
  IFS=$'\t' read -r boot tpm imds arch enc key <<<"$tsv"

  # All five collected before failing, so one run shows every mismatch.
  local mismatch=()
  [[ "$boot" == "uefi" ]]        || mismatch+=("boot mode is ${boot}, expected uefi")
  [[ "$tpm" == "v2.0" ]]         || mismatch+=("TPM support is ${tpm}, expected v2.0")
  [[ "$imds" == "v2.0" ]]        || mismatch+=("IMDS support is ${imds}, expected v2.0")
  [[ "$arch" == "$AMI_ARCH" ]]   || mismatch+=("architecture is ${arch}, expected ${AMI_ARCH}")
  [[ "$enc" == "True" ]]         || mismatch+=("root volume is not encrypted")
  [[ "$key" == "$KMS_KEY_ARN" ]] || mismatch+=("encrypted under ${key}, not ${KMS_KEY_ARN}")

  if ((${#mismatch[@]})); then
    for m in "${mismatch[@]}"; do warn "$m"; done
    # A pod VM missing UEFI or the TPM boots and then fails to attest, which is
    # slow to diagnose -- better to reject the image than hand it over.
    error "${ami} has the wrong properties. Deregister it and delete its snapshot, then re-run."
  fi
  log "Boot properties and encryption as expected"
}

# Same guards as copy-podvm-ami.sh: the layers can be init'd for different
# environments, and verify_ami_properties would not catch a mismatched key.
COMPUTE_ACCOUNT=$(tf_out "$TF_COMPUTE" aws_account_id)
COMPUTE_REGION=$(tf_out "$TF_COMPUTE" aws_region)
INFRA_ACCOUNT=$(tf_out "$TF_INFRA" aws_account_id)
INFRA_REGION=$(tf_out "$TF_INFRA" aws_region)

[[ -n "$COMPUTE_REGION" && -n "$INFRA_REGION" ]] || error \
  "Cannot read terraform state. Run terraform init for 05-compute and 03-infrastructure first."
[[ "$COMPUTE_ACCOUNT" == "$INFRA_ACCOUNT" && "$COMPUTE_REGION" == "$INFRA_REGION" ]] || error \
  "05-compute state is ${COMPUTE_ACCOUNT}/${COMPUTE_REGION} but 03-infrastructure is ${INFRA_ACCOUNT}/${INFRA_REGION}. Re-init both for the same environment."
[[ "$COMPUTE_ACCOUNT" == "$CALLER_ACCOUNT" ]] || error \
  "Credentials are for ${CALLER_ACCOUNT}, but this deployment is ${COMPUTE_ACCOUNT}"

TARGET_REGION="${TARGET_REGION:-$COMPUTE_REGION}"

BUCKET=$(tf_out "$TF_COMPUTE" podvm_import_bucket)
ROLE_NAME=$(tf_out "$TF_COMPUTE" podvm_import_role_name)
KMS_KEY_ARN=$(tf_out "$TF_INFRA" kms_key_general_arn)

[[ -n "$BUCKET" && "$BUCKET" != "null" ]] \
  || error "No staging bucket. Apply 05-compute with -var enable_podvm_image_import=true first."
[[ -n "$ROLE_NAME" && "$ROLE_NAME" != "null" ]] \
  || error "No import role. Apply 05-compute with -var enable_podvm_image_import=true first."
[[ -n "$KMS_KEY_ARN" ]] || error "Could not resolve the general KMS key from 03-infrastructure state"

# A KMS key is regional; import-snapshot rejects one from another region.
KEY_REGION="$(cut -d: -f4 <<<"$KMS_KEY_ARN")"
[[ "$KEY_REGION" == "$TARGET_REGION" ]] \
  || error "KMS key is in ${KEY_REGION} but the import targets ${TARGET_REGION}"

info "Account ${CALLER_ACCOUNT}, region ${TARGET_REGION}"
info "Staging in ${BUCKET} as ${ROLE_NAME}"

#######################################
# Prepare the disk image
#######################################

# VM Import/Export takes RAW or VMDK; the published upstream artifact is qcow2.
case "$IMAGE" in
  *.raw) RAW="$IMAGE" ;;
  *.qcow2)
    command -v qemu-img >/dev/null 2>&1 || error "qemu-img is needed to convert ${IMAGE##*.} to raw"
    # Name the raw after the qcow2's digest, so a leftover conversion of some
    # other image cannot be picked up by matching filename alone.
    QCOW_SHA=$(sha256sum "$IMAGE" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$IMAGE" | cut -d' ' -f1)
    RAW="${IMAGE%.qcow2}-${QCOW_SHA:0:12}.raw"
    if [[ -f "$RAW" ]]; then
      info "Reusing ${RAW} (converted from this exact qcow2)"
    else
      info "Converting to raw"
      qemu-img convert -f qcow2 -O raw "$IMAGE" "$RAW" || error "Conversion failed"
    fi
    ;;
  *) error "Expected a .raw or .qcow2 image, got ${IMAGE}" ;;
esac

SHA=$(sha256sum "$RAW" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$RAW" | cut -d' ' -f1)

# build-podvm-image.sh names the file after the machine it built on. Registering
# an arm64 image as x86_64 produces an AMI that never boots.
case "$RAW" in
  *aarch64*|*arm64*) AMI_ARCH="arm64" ;;
  *)                 AMI_ARCH="x86_64" ;;
esac

# build-podvm-image.sh records what it produced; hold the import to it.
PROV="${IMAGE}.provenance"
CAA_REF="unrecorded"
CAA_COMMIT="unrecorded"
PROVENANCE="imported-artifact"
DESCRIPTION="Conduct sandbox pod VM (imported disk image, no provenance record)"
if [[ -f "$PROV" ]]; then
  # || true: pipefail would otherwise abort with no message on a truncated file.
  CAA_REF=$(grep '^caa_ref=' "$PROV" | cut -d= -f2 || true)
  CAA_COMMIT=$(grep '^caa_commit=' "$PROV" | cut -d= -f2 || true)
  RECORDED=$(grep '^sha256=' "$PROV" | cut -d= -f2 || true)
  [[ -n "$RECORDED" ]] || error "${PROV##*/} has no sha256= line; it is truncated or from an older format"
  MAKE_TARGET=$(grep '^make_target=' "$PROV" | cut -d= -f2 || true)
  if [[ "$RECORDED" != "$SHA" ]]; then
    error "Image does not match its provenance record. Recorded ${RECORDED}, got ${SHA}."
  fi
  DESCRIPTION="Conduct sandbox pod VM (built from ${CAA_REF})"
  if [[ "$MAKE_TARGET" == "debug" ]]; then
    PROVENANCE="built-from-source-debug"
    warn "This is upstream's debug variant: serial console access is enabled."
    warn "Do not use it as a sandbox boundary."
  else
    PROVENANCE="built-from-source"
  fi
  log "Matches its provenance record (${CAA_REF} @ ${CAA_COMMIT:0:12})"
else
  warn "No ${PROV##*/} beside the image — importing without a provenance check"
fi

AMI_NAME="${AMI_NAME:-$(basename "${RAW%.raw}")}"
S3_KEY="$(basename "$RAW")"

# A failed list is not an absent image: collapsing them starts a second
# snapshot import while the first may already exist.
if ! EXISTING=$(aws ec2 describe-images --region "$TARGET_REGION" --owners self \
  --filters "Name=name,Values=${AMI_NAME}" --query 'Images[0].[ImageId,State]' --output text 2>&1); then
  error "Cannot list images in ${TARGET_REGION}: ${EXISTING}"
fi
IFS=$'\t' read -r EXISTING_ID EXISTING_STATE <<<"$EXISTING"
if [[ "$EXISTING_STATE" == "available" ]]; then
  log "Already imported: ${BOLD}${EXISTING_ID}${NC}"
  # A prior run may have registered it and then failed these very checks.
  verify_ami_properties "$EXISTING_ID"
  echo "    Deregister it to re-import, or pass --name for a different name."
  exit 0
elif [[ "$EXISTING_STATE" != "None" && -n "${EXISTING_STATE// /}" ]]; then
  error "An image named ${AMI_NAME} exists in state ${EXISTING_STATE} (${EXISTING_ID}). Deregister it, then run again."
fi

#######################################
# Stage and convert
#######################################

info "Uploading $(du -h "$RAW" | cut -f1) to s3://${BUCKET}/${S3_KEY}"
aws s3 cp "$RAW" "s3://${BUCKET}/${S3_KEY}" --region "$TARGET_REGION" --only-show-errors \
  || error "Upload failed"

# VM Import/Export reads the object for the whole conversion, so it can only be
# removed once the snapshot exists -- not on a timeout or a Ctrl-C, when the
# task is probably still running and is what the script tells you to go check.
SNAPSHOT_DONE=false
cleanup_staged() {
  if [[ "$KEEP_STAGED" == true ]]; then
    return
  fi
  if [[ "$SNAPSHOT_DONE" == false ]]; then
    warn "Leaving s3://${BUCKET}/${S3_KEY} in place — the import may still be reading it"
    warn "Remove it once the task settles, or the bucket lifecycle expires it in 7 days"
    return
  fi
  aws s3 rm "s3://${BUCKET}/${S3_KEY}" --region "$TARGET_REGION" --only-show-errors 2>/dev/null \
    && info "Removed the staged image" || warn "Could not remove s3://${BUCKET}/${S3_KEY}"
}
trap cleanup_staged EXIT

info "Converting to an encrypted snapshot (this is the slow part)"
TASK_ID=$(aws ec2 import-snapshot \
  --region "$TARGET_REGION" \
  --description "Conduct pod VM ${AMI_NAME}" \
  --role-name "$ROLE_NAME" \
  --encrypted --kms-key-id "$KMS_KEY_ARN" \
  --disk-container "Format=RAW,UserBucket={S3Bucket=${BUCKET},S3Key=${S3_KEY}}" \
  --query 'ImportTaskId' --output text) || error "import-snapshot was rejected"
log "Import task ${TASK_ID}"

DEADLINE=$(( $(date +%s) + WAIT_MINUTES * 60 ))
# A throttled or dropped describe call must not be read as a failed import.
UNREADABLE=0
while true; do
  # Tab-delimited: StatusMessage is free text and would shift SnapshotId.
  IFS=$'\t' read -r STATUS MESSAGE SNAPSHOT_ID <<<"$(aws ec2 describe-import-snapshot-tasks \
    --region "$TARGET_REGION" --import-task-ids "$TASK_ID" \
    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.[Status,StatusMessage,SnapshotId]' \
    --output text 2>/dev/null || printf 'unknown\t-\t-')"

  case "$STATUS" in
    completed)
      log "Snapshot ${SNAPSHOT_ID}"; break ;;
    active)
      UNREADABLE=0
      echo "    ${MESSAGE:-converting}" ;;
    unknown)
      UNREADABLE=$(( UNREADABLE + 1 ))
      (( UNREADABLE <= 5 )) || error "Cannot read task ${TASK_ID} after 5 attempts; check it in the console"
      warn "describe-import-snapshot-tasks failed (${UNREADABLE}/5), retrying" ;;
    *)
      error "Import ended as ${STATUS}: ${MESSAGE:-no detail}" ;;
  esac

  (( $(date +%s) < DEADLINE )) || error "Still converting after ${WAIT_MINUTES} minutes; check task ${TASK_ID}"
  sleep 30
done

aws ec2 wait snapshot-completed --region "$TARGET_REGION" --snapshot-ids "$SNAPSHOT_ID" \
  || error "Snapshot ${SNAPSHOT_ID} did not settle"
SNAPSHOT_DONE=true

#######################################
# Register
#######################################

# These four are what the remote hypervisor boots against; a pod VM registered
# without UEFI or a TPM starts and then fails to attest.
info "Registering the AMI"
AMI_ID=$(aws ec2 register-image \
  --region "$TARGET_REGION" \
  --name "$AMI_NAME" \
  --description "$DESCRIPTION" \
  --architecture "$AMI_ARCH" \
  --virtualization-type hvm \
  --root-device-name /dev/xvda \
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=${SNAPSHOT_ID},DeleteOnTermination=true,VolumeType=gp3}" \
  --boot-mode uefi \
  --tpm-support v2.0 \
  --ena-support \
  --imds-support v2.0 \
  --query 'ImageId' --output text) || error "register-image failed. Snapshot ${SNAPSHOT_ID} is now orphaned — delete it before retrying."

aws ec2 create-tags --region "$TARGET_REGION" --resources "$AMI_ID" "$SNAPSHOT_ID" --tags \
  "Key=Name,Value=${AMI_NAME}" \
  "Key=SourceRef,Value=${CAA_REF}" \
  "Key=SourceCommit,Value=${CAA_COMMIT}" \
  "Key=ImageSha256,Value=${SHA}" \
  "Key=Provenance,Value=${PROVENANCE}" >/dev/null || warn "Could not tag ${AMI_ID}"

aws ec2 wait image-available --region "$TARGET_REGION" --image-ids "$AMI_ID" 2>/dev/null || true
log "Registered ${BOLD}${AMI_ID}${NC}"

#######################################
# Verify
#######################################

verify_ami_properties "$AMI_ID"

# Only possible on an AMI we own: trivy cannot read public snapshots.
if [[ "$SKIP_SCAN" == false ]] && command -v trivy >/dev/null 2>&1; then
  info "Scanning the AMI for vulnerabilities (trivy vm is experimental)"
  if ! trivy vm --aws-region "$TARGET_REGION" --scanners vuln,secret --severity HIGH,CRITICAL \
    --exit-code 1 "ami:${AMI_ID}"; then
    warn "The scan above found HIGH/CRITICAL findings, or could not read the image."
    warn "See the pod VM image section of 05-compute/README.md."
    error "${AMI_ID} is registered but did not pass its scan. Review it, then re-run with --skip-scan to accept."
  fi
  log "No HIGH/CRITICAL vulnerabilities or secrets found"
elif [[ "$SKIP_SCAN" == false ]]; then
  warn "trivy not installed; skipping the image scan"
fi

#######################################
# Next steps
#######################################

echo ""
echo -e "${BOLD}Pod VM AMI:${NC} ${AMI_ID}  (${TARGET_REGION})"
echo ""
echo "Set it in 06-applications/<env>/instance-config.yaml:"
echo ""
echo "    aws:"
echo "      sandbox:"
echo "        podvmAmiId: ${AMI_ID}"
echo ""
echo "then re-run the configure step:"
echo ""
echo "    cd 06-applications && ./scripts/configure-instance.sh <env>"
echo ""
info "Turn the staging resources back off: terraform apply -var enable_podvm_image_import=false"
