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
# Exit 0 and the list on stdout. Anything it cannot reach is named on stderr
# and counted; the caller decides whether that is a failure, because a silently
# short list is worse than none.
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
#   - Sources that name a directory of plain manifests rather than a chart.
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

for t in helm yq jq; do command -v "$t" >/dev/null || { echo "missing $t" >&2; exit 2; }; done

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
IMAGES="$WORK/images"; : >"$IMAGES"
UNRESOLVED="$WORK/unresolved"; : >"$UNRESOLVED"

# Keep every index this run downloads inside this run: a cached index is not
# refreshed, so a chart published since the last scan would read as unresolved.
export HELM_REPOSITORY_CACHE="$WORK/helm/cache"
export HELM_REPOSITORY_CONFIG="$WORK/helm/repositories.yaml"

# Registries holding our own artefacts: covered by the product scan, and not
# reachable without credentials the nightly job has no reason to hold.
is_private() { [[ "$1" == ghcr.io/unique-ag/* || "$1" == uniquecr.azurecr.io* || "$1" == *"<"* ]]; }

MISSING=""
# Prints every file a source renders with: the value files it declares, then its
# inline values, which Argo CD lets win. A declared file that is not there fails
# the sync, so a render without it is not what deploys.
render_values() {        # source-yaml
  local src="$1" f missing=() key
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; else missing+=("${f#"$ROOT"/}"); fi
    # $values/<path> refers to the repository root in the ApplicationSet.
  done < <(printf '%s\n' "$src" | yq -N -r '.helm.valueFiles[]?' | sed "s|^\$values/|$ROOT/|")
  if (( ${#missing[@]} > 0 )) \
    && [[ "$(printf '%s\n' "$src" | yq -N -r '.helm.ignoreMissingValueFiles // false')" != "true" ]]; then
    MISSING="${missing[*]}"
    return 1
  fi
  # Most specs set their image here and in no file: without these the render
  # falls back to chart defaults and names an image the environment never pulls.
  for key in valuesObject values; do
    case "$(printf '%s\n' "$src" | yq -N -r ".helm.$key | tag")" in
      '!!map'|'!!str')
        printf '%s\n' "$src" | yq -N -r ".helm.$key" >"$WORK/inline.$key.yaml"
        printf '%s\n' "$WORK/inline.$key.yaml" ;;
    esac
  done
  return 0
}

# The registry this environment pulls third-party images from. configure-instance
# writes it into the overlays from here; before it runs they hold the
# placeholder, so both sources say the same thing either way.
thirdparty_registry() {
  local cfg="$ROOT/06-applications/$ENV/instance-config.yaml" acct region
  if [[ -f "$cfg" ]]; then
    acct=$(yq -N -r '.aws.ecr.thirdParty.accountId // ""' "$cfg" 2>/dev/null || true)
    region=$(yq -N -r '.aws.region // ""' "$cfg" 2>/dev/null || true)
    if [[ -n "$acct" && "$acct" != "null" && -n "$region" && "$region" != "null" ]]; then
      printf '%s.dkr.ecr.%s.amazonaws.com' "$acct" "$region"
      return
    fi
  fi
  printf '%s' '<ECR_REGISTRY_THIRDPARTY_BARE>'
}

# Walking the YAML rather than grepping the text: a container written as
# `- image: x` matches no line filter, and a trailing comment or quote would
# otherwise reach the list.
harvest() {              # label; rendered manifests on stdin
  if yq -N -r '.. | select(tag == "!!map" and has("image")) | .image
                  | select(tag == "!!str" and . != "")' >"$WORK/batch" 2>/dev/null; then
    cat "$WORK/batch" >>"$IMAGES"
  else
    echo "$1 (rendered output could not be read)" >>"$UNRESOLVED"
  fi
}

render() {               # repo chart version values-files...
  local repo="$1" chart="$2" ver="$3"; shift 3
  local args=() f
  if [[ "$repo" == oci://* || "$repo" == ghcr.io/* ]]; then
    args=("oci://${repo#oci://}/$chart")
  else
    # --repo rather than `helm repo add`: it resolves the version against the
    # index it fetches now, and leaves nothing in the caller's helm config.
    args=("$chart" --repo "$repo")
  fi
  for f in "$@"; do args+=(-f "$f"); done
  helm template release "${args[@]}" --version "$ver" 2>/dev/null
}

sources_of() {           # spec-file -- one source per line, as JSON
  yq -N -o=json -I=0 '[.spec.sources[]? // .spec.source] | .[]' "$1" 2>/dev/null
}

while IFS= read -r spec; do
  rel="${spec#"$ROOT"/}"
  # A spec yq cannot read is not a spec with no sources: say so, rather than
  # letting the run look complete without it.
  if ! sources_of "$spec" >"$WORK/sources"; then
    echo "app spec $rel (could not be read)" >>"$UNRESOLVED"
    continue
  fi
  while IFS= read -r src; do
    [[ -n "$src" && "$src" != "null" ]] || continue
    chart=$(printf '%s\n' "$src" | yq -N -r '.chart // ""')
    repo=$(printf '%s\n' "$src" | yq -N -r '.repoURL // ""')
    ver=$(printf '%s\n' "$src" | yq -N -r '.targetRevision // ""')
    path=$(printf '%s\n' "$src" | yq -N -r '.path // ""')

    # A chart vendored into the repository: the spec names a path, not a
    # registry. Render it through the spec that deploys it -- a chart another
    # chart lists under dependencies belongs to that parent's render, where the
    # parent's condition decides whether it ships at all.
    if [[ -z "$chart" || "$chart" == "null" ]]; then
      [[ -n "$path" && "$path" != "null" && -f "$ROOT/$path/Chart.yaml" ]] || continue
      if ! render_values "$src" >"$WORK/vf"; then
        echo "vendored chart $path (value file not found: $MISSING)" >>"$UNRESOLVED"; continue
      fi
      mapfile -t keep <"$WORK/vf"
      cargs=(release "$ROOT/$path" --namespace "$ENV")
      for f in "${keep[@]+"${keep[@]}"}"; do cargs+=(-f "$f"); done
      if cout=$(helm template "${cargs[@]}" 2>/dev/null); then
        printf '%s\n' "$cout" | harvest "vendored chart $path"
      else
        echo "vendored chart $path (render failed)" >>"$UNRESOLVED"
      fi
      continue
    fi

    if is_private "$repo"; then
      echo "$repo/$chart:$ver (private registry)" >>"$UNRESOLVED"; continue
    fi
    if ! render_values "$src" >"$WORK/vf"; then
      echo "$repo/$chart:$ver (value file not found: $MISSING)" >>"$UNRESOLVED"; continue
    fi
    mapfile -t keep <"$WORK/vf"
    if out=$(render "$repo" "$chart" "$ver" "${keep[@]+"${keep[@]}"}"); then
      printf '%s\n' "$out" | harvest "$repo/$chart:$ver"
    else
      echo "$repo/$chart:$ver (render failed)" >>"$UNRESOLVED"
    fi
  done <"$WORK/sources"
done < <(find "$APPS" -name '*.yaml' | sort)

# Artefacts copied by hand carry no chart to render. The manifest holds bare
# repository paths and lists one OCI chart, which no container scanner can read.
MIRROR="$ROOT/06-applications/mirror-artifacts.yaml"
if REG="$(thirdparty_registry)" yq -N -r \
     '.artifacts[] | select((.type // "image") == "image") | strenv(REG) + "/" + .target' \
     "$MIRROR" >"$WORK/mirror" 2>/dev/null; then
  cat "$WORK/mirror" >>"$IMAGES"
else
  echo "${MIRROR#"$ROOT"/} (could not be read)" >>"$UNRESOLVED"
fi

# awk rather than grep for both filters and both counts: grep exits 1 on no
# match, which under pipefail would end the run before it printed the report.
sort -u "$IMAGES" | awk 'NF' >"$WORK/final"
n=$(awk 'END { print NR + 0 }' "$WORK/final")
sort -u "$UNRESOLVED" | awk 'NF' >"$WORK/unresolved.sorted"
u=$(awk 'END { print NR + 0 }' "$WORK/unresolved.sorted")

if $JSON; then
  printf '{"images":%s,"unresolved":%s}\n' \
    "$(jq -R -s -c 'split("\n") | map(select(length > 0))' "$WORK/final")" "$u"
else
  cat "$WORK/final"
fi

{
  echo "---"
  echo "$n image(s) resolved from $ENV"
  if (( u > 0 )); then
    echo "$u source(s) NOT resolved — their images are absent from this list:"
    sed 's/^/  /' "$WORK/unresolved.sorted"
  fi
} >&2
