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
    sed 's/^/    /' "$actual.lint" | head -6
    FAILED=1
    rm -f "$actual" "$actual.lint"
    continue
  fi
  rm -f "$actual.lint"

  if ! helm template "${args[@]}" > "$actual" 2>"$actual.err"; then
    echo "FAIL: $chart did not render"
    sed 's/^/    /' "$actual.err" | head -5
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
    diff -u "$golden" "$actual" | head -25 | sed 's/^/    /'
    FAILED=1
    rm -f "$actual"
  fi
done

# ------------------------------------------------------------------
# Packaged subcharts must match their source directories. helm resolves
# dependencies from the .tgz, so an edited source directory that was never
# repackaged is silently ignored at render time.
# ------------------------------------------------------------------
for tgz in "$CHARTS_DIR"/peerpods/charts/*.tgz; do
  [[ -e "$tgz" ]] || continue
  packaged=$(basename "$tgz" .tgz)
  name="${packaged%-*}"
  src="$CHARTS_DIR/$name"

  if [[ ! -d "$src" ]]; then
    echo "FAIL: $packaged has no source directory at $src"
    FAILED=1
    continue
  fi

  extracted=$(mktemp -d)
  tar xzf "$tgz" -C "$extracted"
  drift=0

  while IFS= read -r rel; do
    a="$extracted/$name/$rel"
    b="$src/$rel"
    if [[ ! -e "$b" ]]; then
      echo "FAIL: $packaged ships $rel, which the source directory does not have"
      drift=1
    elif [[ "$rel" == "Chart.yaml" ]]; then
      # helm package rewrites Chart.yaml (key order, quoting, blank lines),
      # so compare the parsed document rather than the bytes.
      if ! diff <(yq -P 'sort_keys(..)' "$a") <(yq -P 'sort_keys(..)' "$b") >/dev/null; then
        echo "FAIL: $packaged Chart.yaml differs from source beyond formatting"
        diff <(yq -P 'sort_keys(..)' "$a") <(yq -P 'sort_keys(..)' "$b") | head -10 | sed 's/^/    /'
        drift=1
      fi
    elif ! diff -q "$a" "$b" >/dev/null; then
      echo "FAIL: $packaged $rel differs from source — repackage with 'helm dependency update'"
      drift=1
    fi
  done < <(cd "$extracted/$name" && find . -type f | sed 's|^\./||')

  (( drift )) && FAILED=1 || echo "ok:     ${packaged}.tgz matches ./$name"
  rm -rf "$extracted"
done

exit $FAILED
