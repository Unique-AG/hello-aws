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
    -i|--image)      IMAGE="$2"; shift 2 ;;
    -n|--name)       AMI_NAME="$2"; shift 2 ;;
    -r|--region)     TARGET_REGION="$2"; shift 2 ;;
    --keep-staged)   KEEP_STAGED=true; shift ;;
    --skip-scan)     SKIP_SCAN=true; shift ;;
    --wait-minutes)  WAIT_MINUTES="$2"; shift 2 ;;
    -h|--help)       awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)               error "Unknown option: $1 (try --help)" ;;
  esac
done

#######################################
# Pre-checks
#######################################

[[ -n "$IMAGE" ]] || error "No image given (--image PATH, or --help)"
[[ -f "$IMAGE" ]] || error "No such file: ${IMAGE}"

command -v aws >/dev/null 2>&1 || error "aws CLI is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || error "aws CLI has no usable credentials"

CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

EXPECTED_ACCOUNT=$(tf_out "$TF_COMPUTE" aws_account_id)
if [[ -n "$EXPECTED_ACCOUNT" && "$EXPECTED_ACCOUNT" != "$CALLER_ACCOUNT" ]]; then
  error "Credentials are for ${CALLER_ACCOUNT}, but this deployment is ${EXPECTED_ACCOUNT}"
fi

[[ -n "$TARGET_REGION" ]] || TARGET_REGION=$(tf_out "$TF_COMPUTE" aws_region)
TARGET_REGION="${TARGET_REGION:-${AWS_REGION:-eu-central-2}}"

BUCKET=$(tf_out "$TF_COMPUTE" podvm_import_bucket)
ROLE_NAME=$(tf_out "$TF_COMPUTE" podvm_import_role_name)
KMS_KEY_ARN=$(tf_out "$TF_INFRA" kms_key_general_arn)

[[ -n "$BUCKET" && "$BUCKET" != "null" ]] \
  || error "No staging bucket. Apply 05-compute with -var enable_podvm_image_import=true first."
[[ -n "$ROLE_NAME" && "$ROLE_NAME" != "null" ]] \
  || error "No import role. Apply 05-compute with -var enable_podvm_image_import=true first."
[[ -n "$KMS_KEY_ARN" ]] || error "Could not resolve the general KMS key from 03-infrastructure state"

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
    RAW="${IMAGE%.qcow2}.raw"
    if [[ -f "$RAW" ]]; then
      info "Reusing ${RAW}"
    else
      info "Converting to raw"
      qemu-img convert -f qcow2 -O raw "$IMAGE" "$RAW" || error "Conversion failed"
    fi
    ;;
  *) error "Expected a .raw or .qcow2 image, got ${IMAGE}" ;;
esac

SHA=$(sha256sum "$RAW" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$RAW" | cut -d' ' -f1)

# build-podvm-image.sh records what it produced; hold the import to it.
PROV="${IMAGE}.provenance"
CAA_REF="unrecorded"
CAA_COMMIT="unrecorded"
PROVENANCE="imported-artifact"
if [[ -f "$PROV" ]]; then
  CAA_REF=$(grep '^caa_ref=' "$PROV" | cut -d= -f2)
  CAA_COMMIT=$(grep '^caa_commit=' "$PROV" | cut -d= -f2)
  RECORDED=$(grep '^sha256=' "$PROV" | cut -d= -f2)
  if [[ "$RECORDED" != "$SHA" ]]; then
    error "Image does not match its provenance record. Recorded ${RECORDED}, got ${SHA}."
  fi
  PROVENANCE="built-from-source"
  log "Matches its provenance record (${CAA_REF} @ ${CAA_COMMIT:0:12})"
else
  warn "No ${PROV##*/} beside the image — importing without a provenance check"
fi

AMI_NAME="${AMI_NAME:-$(basename "${RAW%.raw}")}"
S3_KEY="$(basename "$RAW")"

EXISTING=$(aws ec2 describe-images --region "$TARGET_REGION" --owners self \
  --filters "Name=name,Values=${AMI_NAME}" --query 'Images[0].[ImageId,State]' --output text 2>/dev/null || echo "None None")
read -r EXISTING_ID EXISTING_STATE <<<"$EXISTING"
if [[ "$EXISTING_STATE" == "available" ]]; then
  log "Already imported: ${BOLD}${EXISTING_ID}${NC}"
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

cleanup_staged() {
  if [[ "$KEEP_STAGED" == false ]]; then
    aws s3 rm "s3://${BUCKET}/${S3_KEY}" --region "$TARGET_REGION" --only-show-errors 2>/dev/null \
      && info "Removed the staged image" || warn "Could not remove s3://${BUCKET}/${S3_KEY}"
  fi
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
while true; do
  read -r STATUS MESSAGE SNAPSHOT_ID <<<"$(aws ec2 describe-import-snapshot-tasks \
    --region "$TARGET_REGION" --import-task-ids "$TASK_ID" \
    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.[Status,StatusMessage,SnapshotId]' \
    --output text 2>/dev/null || echo "unknown - -")"

  case "$STATUS" in
    completed) log "Snapshot ${SNAPSHOT_ID}"; break ;;
    active)    echo "    ${MESSAGE:-converting}" ;;
    *)         error "Import ended as ${STATUS}: ${MESSAGE:-no detail}" ;;
  esac

  (( $(date +%s) < DEADLINE )) || error "Still converting after ${WAIT_MINUTES} minutes; check task ${TASK_ID}"
  sleep 30
done

aws ec2 wait snapshot-completed --region "$TARGET_REGION" --snapshot-ids "$SNAPSHOT_ID" \
  || error "Snapshot ${SNAPSHOT_ID} did not settle"

#######################################
# Register
#######################################

# These four are what the remote hypervisor boots against; a pod VM registered
# without UEFI or a TPM starts and then fails to attest.
info "Registering the AMI"
AMI_ID=$(aws ec2 register-image \
  --region "$TARGET_REGION" \
  --name "$AMI_NAME" \
  --description "Conduct sandbox pod VM (built from ${CAA_REF})" \
  --architecture x86_64 \
  --virtualization-type hvm \
  --root-device-name /dev/xvda \
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=${SNAPSHOT_ID},DeleteOnTermination=true,VolumeType=gp3}" \
  --boot-mode uefi \
  --tpm-support v2.0 \
  --ena-support \
  --imds-support v2.0 \
  --query 'ImageId' --output text) || error "register-image failed"

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

read -r R_BOOT R_TPM R_ENC R_KEY <<<"$(aws ec2 describe-images --region "$TARGET_REGION" --image-ids "$AMI_ID" \
  --query 'Images[0].[BootMode,TpmSupport,BlockDeviceMappings[0].Ebs.Encrypted,BlockDeviceMappings[0].Ebs.KmsKeyId]' \
  --output text)"
[[ "$R_BOOT" == "uefi" ]]  || warn "Registered boot mode is ${R_BOOT}, expected uefi"
[[ "$R_TPM" == "v2.0" ]]   || warn "Registered TPM support is ${R_TPM}, expected v2.0"
[[ "$R_ENC" == "True" ]]   || warn "Root volume is not encrypted"
[[ "$R_KEY" == "$KMS_KEY_ARN" ]] || warn "Encrypted under ${R_KEY}, not ${KMS_KEY_ARN}"

# Only possible on an AMI we own: trivy cannot read public snapshots.
if [[ "$SKIP_SCAN" == false ]] && command -v trivy >/dev/null 2>&1; then
  info "Scanning the AMI for vulnerabilities (trivy vm is experimental)"
  trivy vm --aws-region "$TARGET_REGION" --scanners vuln,secret --severity HIGH,CRITICAL \
    "ami:${AMI_ID}" || warn "trivy could not scan the image; see the pod VM image section of 05-compute/README.md"
elif [[ "$SKIP_SCAN" == false ]]; then
  warn "trivy not installed; skipping the image scan"
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
info "Turn the staging resources back off: terraform apply -var enable_podvm_image_import=false"
