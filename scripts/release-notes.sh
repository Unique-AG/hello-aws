#!/bin/bash
set -euo pipefail

#######################################
# Release Notes Generator
#######################################
#
# Renders the body of a GitHub Release for a release tag:
# 1. Upgrade notes from docs/releases/<tag>.md, when that file exists
# 2. The Unique platform release the tag corresponds to
# 3. A component version table from the app specs, diffed against the previous tag
#
# The pull-request changelog is appended by GitHub (gh release create --generate-notes).
#
# Usage:
#   ./scripts/release-notes.sh <previous_tag|""> <tag>
#
# Examples:
#   ./scripts/release-notes.sh 2026.37.0 2026.40.4
#   ./scripts/release-notes.sh "" 2026.37.0        # first release, no comparison
#
# Requires: git, yq (mikefarah v4)

PREV="${1:-}"
TAG="${2:?usage: release-notes.sh <previous_tag|\"\"> <tag>}"
APPS_DIR="06-applications/sbx/apps"

# Prints one "name<TAB>chart@version<TAB>image" line per app spec at a git ref.
components_at() {
  local ref="$1" file
  local files
  files=$(git ls-tree -r --name-only "$ref" -- "$APPS_DIR" | grep -E '\.ya?ml$' | sort)
  for file in $files; do
    # shellcheck disable=SC2016 # $s, $charts, $images are yq variables
    git show "$ref:$file" | yq -r '
      .spec as $s
      | [ $s.sources[] | select(.chart != null and .chart != "raw")
          | (.chart | sub("^helm/"; "") | sub("^\.$"; "(git)")) + "@" + (.targetRevision | tostring | sub("^(sha256:[0-9a-f]{12}).*"; "${1}")) ] as $charts
      | [ $s.sources[] | select(.helm.valuesObject.image.tag != null) | .helm.valuesObject.image.tag ] as $images
      | [ $s.name, ($charts | join(", ")), ($images | join(", ")) ] | join("\t")' \
      || { echo "release-notes: cannot parse ${ref}:${file}" >&2; return 1; }
  done
}

if [[ -f "docs/releases/${TAG}.md" ]]; then
  cat "docs/releases/${TAG}.md"
  echo
fi

echo "## Unique platform"
echo
echo "Unique \`${TAG}\` — see the [Unique Release Notes & Calendar](https://docs.unique.ai/it-operators/installing-and-upgrading-unique/release-notes-and-calendar) for application changes."
echo
echo "## Component versions"
echo
if [[ -n "$PREV" ]]; then
  echo "Changed since \`${PREV}\` are marked **bold**. Full diff: \`git diff ${PREV} ${TAG} -- ${APPS_DIR}\`"
  echo
fi
echo "| Application | Chart | Image tag |"
echo "|---|---|---|"

# Collected up front so a parse failure aborts the script under set -e.
current_rows=$(components_at "$TAG")
declare -A prev_line=()
if [[ -n "$PREV" ]]; then
  prev_rows=$(components_at "$PREV")
  while IFS=$'\t' read -r name charts image; do
    prev_line["$name"]="${charts}"$'\t'"${image}"
  done <<< "$prev_rows"
fi

while IFS=$'\t' read -r name charts image; do
  old="${prev_line[$name]-}"
  chart_cell="${charts:-—}"
  image_cell="${image:-—}"
  if [[ -n "$PREV" ]]; then
    if [[ -z "$old" ]]; then
      name="${name} _(new)_"
    else
      [[ "${old%%$'\t'*}" != "$charts" ]] && chart_cell="**${chart_cell}** (was ${old%%$'\t'*})"
      [[ "${old#*$'\t'}" != "$image" ]] && image_cell="**${image_cell}** (was ${old#*$'\t'})"
    fi
  fi
  echo "| \`${name}\` | ${chart_cell} | ${image_cell} |"
done <<< "$current_rows"
