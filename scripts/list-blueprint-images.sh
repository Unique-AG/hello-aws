#!/usr/bin/env bash
# list-blueprint-images.sh — every container image an environment deploys.
#
# The nightly scan needs a list that cannot drift from what is actually
# deployed, so this renders the charts the app specs name, with the value files
# those specs pass, rather than reading images out of the overlays. Chart
# defaults supply most third-party images and appear in no file here; rendering
# with defaults instead of our values invents images we never deploy.
#
# Usage:
#   scripts/list-blueprint-images.sh <env> [--json]
#
# Exit 0 and the list on stdout. Charts it cannot reach are named on stderr and
# counted; the caller decides whether an unresolved chart is a failure, because
# a silently short list is worse than none.
#
# Coverage, measured against the images running on sbx on 2026-11-18: 38 of 47
# third-party images, 80%. What it cannot see, and why:
#
#   - Operator-derived images. ECK builds the Elasticsearch reference from
#     spec.version on the custom resource, and the RabbitMQ operator does the
#     same; neither appears as an image field in any rendered manifest. These
#     cannot be reached by rendering at all -- read them from a running cluster,
#     or from the operator's version mapping.
#   - Charts on registries needing credentials (our own product charts).
#   - A few sub-chart images behind conditions this environment does not set.
#
# So treat the output as a floor, not an inventory: everything listed is
# deployed, but something deployed may be missing. Anything that must be
# exhaustive has to reconcile this against a cluster.
set -euo pipefail

ENV="${1:-}"
[[ -n "$ENV" ]] || { echo "usage: $0 <env> [--json]" >&2; exit 2; }
JSON=false
[[ "${2:-}" == "--json" ]] && JSON=true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS="$ROOT/06-applications/$ENV/apps"
[[ -d "$APPS" ]] || { echo "no apps for env '$ENV'" >&2; exit 2; }

for t in helm yq; do command -v "$t" >/dev/null || { echo "missing $t" >&2; exit 2; }; done

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
IMAGES="$WORK/images"; : >"$IMAGES"
UNRESOLVED="$WORK/unresolved"; : >"$UNRESOLVED"

# Registries holding our own artefacts: covered by the product scan, and not
# reachable without credentials the nightly job has no reason to hold.
is_private() { [[ "$1" == ghcr.io/unique-ag/* || "$1" == uniquecr.azurecr.io* || "$1" == *"<"* ]]; }

render() {               # repo chart version values-files...
  local repo="$1" chart="$2" ver="$3"; shift 3
  local name args=()
  name="$(printf '%s' "$repo" | tr -c 'a-zA-Z0-9' '-' )"
  if [[ "$repo" == oci://* || "$repo" == ghcr.io/* ]]; then
    args=("oci://${repo#oci://}/$chart")
  else
    helm repo add "$name" "$repo" >/dev/null 2>&1 || return 1
    args=("$name/$chart")
  fi
  local f
  for f in "$@"; do [[ -f "$f" ]] && args+=(-f "$f"); done
  helm template release "${args[@]}" --version "$ver" 2>/dev/null
}

while IFS= read -r spec; do
  count=$(yq -r '[.spec.sources[]? // .spec.source] | length' "$spec" 2>/dev/null || echo 0)
  for i in $(seq 0 $((count - 1))); do
    src=$(yq -r "[.spec.sources[]? // .spec.source][$i]" "$spec" 2>/dev/null) || continue
    chart=$(echo "$src" | yq -r '.chart // ""'); [[ -n "$chart" && "$chart" != "null" ]] || continue
    repo=$(echo "$src" | yq -r '.repoURL // ""')
    ver=$(echo "$src" | yq -r '.targetRevision // ""')
    if is_private "$repo"; then
      echo "$repo/$chart:$ver" >>"$UNRESOLVED"; continue
    fi
    # $values/<path> refers to the repository root in the ApplicationSet.
    mapfile -t vf < <(echo "$src" | yq -r '.helm.valueFiles[]?' | sed "s|^\$values/|$ROOT/|")
    if out=$(render "$repo" "$chart" "$ver" "${vf[@]+"${vf[@]}"}"); then
      # Grepping the rendered text rather than walking it: a multi-document
      # render makes yq's recursive descent awkward, and `image:` is unambiguous.
      printf '%s\n' "$out" | grep -E '^[[:space:]]*image:[[:space:]]' \
        | sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' \
        | grep -vE '^[[:space:]]*$|^null$' >>"$IMAGES" || true
    else
      echo "$repo/$chart:$ver (render failed)" >>"$UNRESOLVED"
    fi
  done
done < <(find "$APPS" -name '*.yaml' | sort)

# Charts vendored into the repository: deployed like the rest, but no app spec
# names a registry for them.
for cdir in "$ROOT"/06-applications/charts/*/; do
  [[ -f "$cdir/Chart.yaml" ]] || continue
  cname=$(basename "$cdir")
  cvals=("$ROOT/06-applications/$ENV/value-overlays/conduct/$cname.yaml")
  cargs=(release "$cdir" --namespace "$ENV")
  [[ -f "${cvals[0]}" ]] && cargs+=(-f "${cvals[0]}")
  if cout=$(helm template "${cargs[@]}" 2>/dev/null); then
    printf '%s\n' "$cout" | grep -E '^[[:space:]]*image:[[:space:]]' \
      | sed -E 's/^[[:space:]]*image:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' \
      | grep -vE '^[[:space:]]*$|^null$' >>"$IMAGES" || true
  else
    echo "vendored chart $cname (render failed)" >>"$UNRESOLVED"
  fi
done

# Images copied by hand carry no chart to render.
yq -r '.artifacts[].target' "$ROOT/06-applications/mirror-artifacts.yaml" 2>/dev/null >>"$IMAGES" || true

sort -u "$IMAGES" | grep -vE '^\s*$' >"$WORK/final"
n=$(grep -c '' "$WORK/final" || echo 0)
u=$(sort -u "$UNRESOLVED" | grep -c '' || echo 0)

if $JSON; then
  printf '{"images":['
  sed 's/.*/"&"/' "$WORK/final" | paste -sd, -
  printf '],"unresolved":%s}\n' "$u"
else
  cat "$WORK/final"
fi

{
  echo "---"
  echo "$n image(s) resolved from $ENV"
  if (( u > 0 )); then
    echo "$u chart(s) NOT resolved — their images are absent from this list:"
    sort -u "$UNRESOLVED" | sed 's/^/  /'
  fi
} >&2
