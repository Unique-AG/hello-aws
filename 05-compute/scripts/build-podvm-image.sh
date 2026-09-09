#!/usr/bin/env bash
#######################################
# Conduct Pod VM Image Build Script
#######################################
#
# Builds the Confidential Containers pod VM disk image from source with mkosi,
# pinned to the CAA version the peerpods chart vendors, and prints the SHA256
# of the result for import-podvm-ami.sh to verify.
#
# Runs the upstream build unmodified — this only pins the version, checks the
# host, and reports what came out. Requires Linux with Docker; the mkosi build
# needs a privileged container and cannot run on macOS.
#
# Usage:
#   ./build-podvm-image.sh [options]
#
# Options:
#   -r, --ref REF         CAA git ref to build (default: the pinned version)
#   -o, --out DIR         Where to place the image (default: ./podvm-build)
#       --debug-image     Build upstream's debug variant instead
#       --no-verify-provenance
#                         Skip attestation checks on upstream's binaries
#       --check           Check host prerequisites and exit
#   -h, --help            Show this help message
#
# Examples:
#   # Confirm the host can build before committing to it
#   ./build-podvm-image.sh --check
#
#   # Build the pinned version
#   ./build-podvm-image.sh
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

# Must match the appVersion of 06-applications/charts/peerpods.
PINNED_REF="v0.22.0"
CAA_REPO="https://github.com/confidential-containers/cloud-api-adaptor"

# Upstream's own build host, for reference when a dependency is missing.
APT_DEPS=(alien bubblewrap dnf qemu-utils uidmap)

CAA_REF="$PINNED_REF"
OUT_DIR="$(pwd)/podvm-build"
MAKE_TARGET="all"
CHECK_ONLY=false
# Upstream defaults this off. On, the build verifies GitHub attestations for the
# kata-agent and guest-component binaries it pulls before baking them in.
VERIFY_PROVENANCE="yes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--ref)       CAA_REF="$2"; shift 2 ;;
    -o|--out)       OUT_DIR="$2"; shift 2 ;;
    --debug-image)  MAKE_TARGET="debug"; shift ;;
    --no-verify-provenance) VERIFY_PROVENANCE="no"; shift ;;
    --check)        CHECK_ONLY=true; shift ;;
    -h|--help)      awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)              error "Unknown option: $1 (try --help)" ;;
  esac
done

#######################################
# Host prerequisites
#######################################

MISSING=()

[[ "$(uname -s)" == "Linux" ]] \
  || error "The mkosi build needs Linux with Docker; this is $(uname -s). Run it on a Linux host or a CI runner."

command -v docker >/dev/null 2>&1 || MISSING+=("docker")
docker buildx version >/dev/null 2>&1 || MISSING+=("docker-buildx")
command -v git >/dev/null 2>&1 || MISSING+=("git")
command -v qemu-img >/dev/null 2>&1 || MISSING+=("qemu-utils")
# The Makefile's pull_agent_artifact/pull_gc_artifact run oras on the host.
command -v oras >/dev/null 2>&1 || MISSING+=("oras")
if [[ "$VERIFY_PROVENANCE" == "yes" ]]; then
  command -v gh >/dev/null 2>&1 || MISSING+=("gh (or pass --no-verify-provenance)")
fi

for c in bwrap dnf; do
  command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
done

if command -v yq >/dev/null 2>&1; then
  yq --version 2>&1 | grep -qE 'v?4\.[0-9]+' || MISSING+=("yq-4.x (found $(yq --version 2>&1))")
else
  MISSING+=("yq-4.x")
fi

if ((${#MISSING[@]})); then
  warn "Missing prerequisites: ${MISSING[*]}"
  echo ""
  echo "On Debian/Ubuntu, upstream's build host installs:"
  echo "    sudo apt-get install -y ${APT_DEPS[*]}"
  echo "    # plus Docker with buildx, and yq 4.x"
  $CHECK_ONLY && exit 1
  error "Cannot build until these are present"
fi

docker info >/dev/null 2>&1 || { $CHECK_ONLY && { warn "Docker is installed but not usable by this user"; exit 1; }; error "Docker is not usable by this user"; }

log "Host looks able to build"
if $CHECK_ONLY; then
  info "Would build ${CAA_REF} into ${OUT_DIR}"
  exit 0
fi

#######################################
# Fetch the pinned source
#######################################

[[ "$CAA_REF" == "$PINNED_REF" ]] \
  || warn "Building ${CAA_REF}, not the pinned ${PINNED_REF} — the image must match the chart's appVersion"

mkdir -p "$OUT_DIR"
SRC_DIR="${OUT_DIR}/cloud-api-adaptor"

if [[ -d "$SRC_DIR/.git" ]]; then
  info "Reusing ${SRC_DIR}"
  git -C "$SRC_DIR" fetch --depth 1 origin "$CAA_REF" --quiet
  git -C "$SRC_DIR" checkout --quiet FETCH_HEAD
else
  info "Cloning ${CAA_REF}"
  git clone --depth 1 --branch "$CAA_REF" --quiet "$CAA_REPO" "$SRC_DIR"
fi

SRC_SHA=$(git -C "$SRC_DIR" rev-parse HEAD)
log "Source at ${SRC_SHA}"

PODVM_DIR="${SRC_DIR}/src/cloud-api-adaptor/podvm"
[[ -d "$PODVM_DIR" ]] || error "No podvm directory at ${CAA_REF}; the upstream layout has moved"

#######################################
# Build
#######################################

# TEE_PLATFORM is left at its default of "none": the overlay sets
# DISABLECVM=true, so no attester beyond the filesystem one is needed.
MKOSI_VERSION=$(yq -e '.tools.mkosi' "${SRC_DIR}/src/cloud-api-adaptor/versions.yaml")
info "mkosi ${MKOSI_VERSION}, target '${MAKE_TARGET}', TEE_PLATFORM=none"
if [[ "$VERIFY_PROVENANCE" == "yes" ]]; then
  info "Verifying upstream binary attestations as they are pulled"
else
  warn "Provenance verification disabled — upstream binaries are taken on trust"
fi
warn "This takes a while and needs a privileged container"

make -C "$PODVM_DIR" "$MAKE_TARGET" \
  MKOSI_VERSION="$MKOSI_VERSION" \
  VERIFY_PROVENANCE="$VERIFY_PROVENANCE"

RAW="${PODVM_DIR}/build/system.raw"
[[ -f "$RAW" ]] || error "Build finished but ${RAW} is missing"

#######################################
# Report
#######################################

FINAL="${OUT_DIR}/podvm-${CAA_REF}-$(uname -m).raw"
mv "$RAW" "$FINAL"
SHA=$(sha256sum "$FINAL" | cut -d' ' -f1)

# Recorded next to the image so the import can prove it got this artifact.
cat > "${FINAL}.provenance" <<PROV
caa_ref=${CAA_REF}
caa_commit=${SRC_SHA}
mkosi_version=${MKOSI_VERSION}
make_target=${MAKE_TARGET}
verify_provenance=${VERIFY_PROVENANCE}
tee_platform=none
sha256=${SHA}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROV

echo ""
log "Built ${BOLD}${FINAL}${NC}"
echo "    size:   $(du -h "$FINAL" | cut -f1)"
echo "    sha256: ${SHA}"
echo "    source: ${CAA_REF} @ ${SRC_SHA}"
echo ""
echo "Import it with:"
echo ""
echo "    ./05-compute/scripts/import-podvm-ami.sh --image ${FINAL}"
echo ""
[[ "$MAKE_TARGET" == "debug" ]] && warn "Debug variant: serial console access is enabled. Do not use it as a sandbox boundary."
exit 0
