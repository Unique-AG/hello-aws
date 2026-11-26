#!/usr/bin/env bash
# scan-podvm-raw.sh — scan a pod VM raw image before it becomes an AMI (CA 9.3).
#
# `trivy vm` cannot read this image: the root is squashfs under dm-verity, and
# trivy reports "OS is not detected", scans nothing and exits 0. So the root is
# attached, mounted read-only and scanned as a filesystem, which is the method
# 05-compute/README.md records as working.
#
# It fails closed. A missing scanner, an unreadable image or a scan that
# enumerated nothing are all failures, not passes: this image becomes the root
# filesystem of every sandbox, and "nothing found" must never mean "not looked".
#
# Usage: scan-podvm-raw.sh --image <raw> [--accept <file>]
#
#   --accept  Findings accepted despite the rules, one "<ID> <YYYY-MM-DD> <record>"
#             per line. An entry past its date does not apply.

set -euo pipefail

IMAGE=""
ACCEPT=""
LOOP=""
MNT=""

log()   { printf '\033[0;32m%s\033[0m\n' "$*"; }
info()  { printf '%s\n' "$*"; }
warn()  { printf '\033[0;33m%s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31m%s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  [[ -n "$MNT"  ]] && mountpoint -q "$MNT" && sudo umount "$MNT" 2>/dev/null || true
  [[ -n "$LOOP" ]] && sudo losetup -d "$LOOP" 2>/dev/null || true
  [[ -n "$MNT"  ]] && rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)  IMAGE="$2"; shift 2 ;;
    --accept) ACCEPT="$2"; shift 2 ;;
    *) error "unknown argument: $1" ;;
  esac
done

[[ -n "$IMAGE" ]]  || error "--image is required"
[[ -f "$IMAGE" ]]  || error "no such image: $IMAGE"

# A missing tool means the image is unscanned. The import script treats that as
# a warning; here it is a failure, because nothing downstream looks again.
for tool in trivy jq losetup; do
  command -v "$tool" >/dev/null 2>&1 || error "$tool is not installed; the image cannot be scanned"
done

info "Attaching ${IMAGE}"
LOOP=$(sudo losetup --find --partscan --read-only --show "$IMAGE")
MNT=$(mktemp -d)

# The root is whichever partition mounts as squashfs; the image's layout has
# changed across peer-pod releases, so it is found rather than assumed.
root=""
for part in "${LOOP}"p*; do
  [[ -b "$part" ]] || continue
  if sudo mount -o ro,nosuid,nodev "$part" "$MNT" 2>/dev/null; then
    if [[ -d "$MNT/usr" || -d "$MNT/etc" ]]; then root="$part"; break; fi
    sudo umount "$MNT"
  fi
done
[[ -n "$root" ]] || error "no partition in ${IMAGE} mounted as a root filesystem; the image is UNSCANNED"
log "Mounted ${root} read-only"

report=$(mktemp)
rc=0
trivy rootfs --scanners vuln,secret --severity HIGH,CRITICAL \
  --exit-code 1 --format json --output "$report" "$MNT" || rc=$?

# 1 is "findings", handled below from the report. Anything else is trivy
# failing, which must not read as a clean image.
if (( rc > 1 )); then
  error "trivy exited ${rc} scanning ${IMAGE}; the image is UNSCANNED"
fi

# trivy exits 0 on a tree it could not analyse, so an empty result set is
# "not looked at", not "clean". The image carries no dpkg database, so OS
# packages cannot be enumerated at all — a zero package count is expected and
# is not evidence of anything.
targets=$(jq -r '[.Results[]?] | length' "$report")
if [[ "$targets" -eq 0 ]]; then
  error "${IMAGE} is UNSCANNED: trivy produced no results for the mounted root."
fi

findings=$(jq -r '
  (.Results[]?.Vulnerabilities[]? | "\(.VulnerabilityID) \(.Severity) \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion // "no fix")"),
  (.Results[]?.Secrets[]?        | "SECRET-\(.RuleID) \(.Title)")' "$report" | sort -u)

if [[ -n "$ACCEPT" && -f "$ACCEPT" ]]; then
  today=$(date -u +%F)
  while read -r id expiry record; do
    [[ -z "${id:-}" || "$id" == \#* ]] && continue
    if [[ -z "${record:-}" ]]; then
      error "acceptance for ${id} names no exception record; CA 9.3 requires one"
    fi
    if [[ "$expiry" < "$today" ]]; then
      warn "acceptance for ${id} expired on ${expiry}; it no longer applies"
      continue
    fi
    findings=$(printf '%s\n' "$findings" | grep -v "^${id} " || true)
    info "accepted ${id} until ${expiry} (${record})"
  done < "$ACCEPT"
fi

if [[ -n "$findings" ]]; then
  printf '%s\n' "$findings" | head -40 | sed 's/^/  /'
  warn "Full report kept at ${report}"
  error "${IMAGE} did not pass its scan. Accept a finding only with an expiry date and an exception record."
fi

rm -f "$report"
log "No HIGH/CRITICAL vulnerabilities or secrets in ${targets} scanned target(s)"
