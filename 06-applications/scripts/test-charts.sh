#!/usr/bin/env bash
# test-charts.sh — Lint and render every vendored chart, comparing against committed output.
#
# Usage:
#   ./scripts/test-charts.sh          # verify against the golden files
#   ./scripts/test-charts.sh --update # rewrite the golden files
#
# Exit code 0 = rendered output matches, 1 = it drifted or a chart failed to render.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTS_DIR="$BASE_DIR/charts"
GOLDEN_DIR="$CHARTS_DIR/.golden"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

# chart:values-file (empty values = chart defaults). The overlay is the real
# deployment path, so it is the case that must not drift unnoticed.
CASES=(
  "peerpods:$BASE_DIR/sbx/value-overlays/conduct/peer-pods.yaml"
  "peerpods-webhook:"
  "peerpodctrl:"
)

mkdir -p "$GOLDEN_DIR"
FAILED=0

for case in "${CASES[@]}"; do
  chart="${case%%:*}"
  values="${case#*:}"
  golden="$GOLDEN_DIR/${chart}.yaml"
  actual=$(mktemp)

  args=("$chart" "$CHARTS_DIR/$chart" --namespace sbx)
  [[ -n "$values" ]] && args+=(-f "$values")

  # Lint with the same values as the render: peerpods templates an index over
  # providerConfigs, which is nil until an overlay supplies it.
  lint_args=("$CHARTS_DIR/$chart" --quiet)
  [[ -n "$values" ]] && lint_args+=(-f "$values")
  if ! helm lint "${lint_args[@]}" >"$actual.lint" 2>&1; then
    echo "FAIL: $chart did not lint"
    sed 's/^/    /' "$actual.lint" | head -6 || true
    FAILED=1
    rm -f "$actual" "$actual.lint"
    continue
  fi
  rm -f "$actual.lint"

  if ! helm template "${args[@]}" > "$actual" 2>"$actual.err"; then
    echo "FAIL: $chart did not render"
    sed 's/^/    /' "$actual.err" | head -5 || true
    FAILED=1
    rm -f "$actual" "$actual.err"
    continue
  fi
  rm -f "$actual.err"

  if (( UPDATE )); then
    mv "$actual" "$golden"
    echo "updated: ${chart}.yaml ($(wc -l < "$golden" | tr -d ' ') lines)"
  elif [[ ! -f "$golden" ]]; then
    echo "FAIL: $chart has no golden file — run with --update"
    FAILED=1
    rm -f "$actual"
  elif diff -u "$golden" "$actual" > /dev/null; then
    echo "ok:     ${chart}.yaml"
    rm -f "$actual"
  else
    echo "FAIL: $chart rendered output drifted"
    diff -u "$golden" "$actual" | head -25 | sed 's/^/    /' || true
    FAILED=1
    rm -f "$actual"
  fi
done

# Packaged subcharts must match their sources: helm resolves dependencies from
# the .tgz, so an unrepackaged source edit is ignored at render time.
for tgz in "$CHARTS_DIR"/peerpods/charts/*.tgz; do
  [[ -e "$tgz" ]] || continue
  packaged=$(basename "$tgz" .tgz)
  src="$CHARTS_DIR/${packaged%-*}"

  if [[ ! -d "$src" ]]; then
    echo "FAIL: $packaged has no source directory at $src"
    FAILED=1
    continue
  fi

  work=$(mktemp -d)
  # Repackaging and comparing both archives covers files added or removed on
  # either side, and applies .helmignore exactly as a real dependency build would.
  if ! helm package "$src" -d "$work" >/dev/null 2>&1; then
    echo "FAIL: $packaged could not be repackaged from $src"
    FAILED=1
    rm -rf "$work"
    continue
  fi

  fresh=$(find "$work" -maxdepth 1 -name '*.tgz' | head -1)
  if [[ "$(basename "$fresh" .tgz)" != "$packaged" ]]; then
    echo "FAIL: $packaged is stale — the source now packages as $(basename "$fresh" .tgz)"
    FAILED=1
    rm -rf "$work"
    continue
  fi

  mkdir -p "$work/committed" "$work/rebuilt"
  tar xzf "$tgz" -C "$work/committed"
  tar xzf "$fresh" -C "$work/rebuilt"

  if diff -r "$work/committed" "$work/rebuilt" >/dev/null 2>&1; then
    echo "ok:     ${packaged}.tgz matches ./$(basename "$src")"
  else
    echo "FAIL: ${packaged}.tgz differs from its source — run 'helm dependency update'"
    diff -r "$work/committed" "$work/rebuilt" 2>&1 | head -12 | sed 's/^/    /' || true
    FAILED=1
  fi
  rm -rf "$work"
done

exit $FAILED
