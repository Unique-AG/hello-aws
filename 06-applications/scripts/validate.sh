#!/usr/bin/env bash
#######################################
# Application Manifest Validation Script
#######################################
#
# Validates 06-applications layer manifests:
# 1. YAML syntax (yamllint)
# 2. Shell script linting (shellcheck)
# 3. Value file reference integrity
# 4. Placeholder validation (via validate-instance.sh)
#
# Usage:
#   cd 06-applications
#   ./scripts/validate.sh <env>
#   ./scripts/validate.sh sbx
#
# Options:
#   --skip-placeholders  Skip placeholder token validation
#
# Exit code 0 = clean, 1 = validation failed
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$BASE_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VALIDATION_FAILED=false

# Portable relative path (macOS-compatible, no GNU realpath)
relpath() {
  echo "${1#"$BASE_DIR/"}"
}

# Parse arguments
ENV=""
SKIP_PLACEHOLDERS=false

for arg in "$@"; do
  case "$arg" in
    --skip-placeholders) SKIP_PLACEHOLDERS=true ;;
    -*) echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
    *) ENV="$arg" ;;
  esac
done

if [[ -z "$ENV" ]]; then
  echo -e "${RED}Usage: $0 <env> [--skip-placeholders]${NC}"
  echo -e "${YELLOW}  e.g. $0 sbx${NC}"
  exit 1
fi

ENV_DIR="$BASE_DIR/$ENV"

if [[ ! -d "$ENV_DIR" ]]; then
  echo -e "${RED}ERROR: Environment directory $ENV_DIR not found.${NC}"
  exit 1
fi

#######################################
# Check Prerequisites
#######################################
echo -e "${YELLOW}Checking prerequisites...${NC}"

YAMLLINT_AVAILABLE=false
SHELLCHECK_AVAILABLE=false
GITLEAKS_AVAILABLE=false

if command -v yamllint &>/dev/null; then
  YAMLLINT_AVAILABLE=true
  echo -e "${GREEN}  yamllint found${NC}"
else
  echo -e "${YELLOW}  yamllint not found (optional, skipping YAML linting)${NC}"
fi

if command -v shellcheck &>/dev/null; then
  SHELLCHECK_AVAILABLE=true
  echo -e "${GREEN}  shellcheck found${NC}"
else
  echo -e "${YELLOW}  shellcheck not found (optional, skipping shell linting)${NC}"
fi

if command -v gitleaks &>/dev/null; then
  GITLEAKS_AVAILABLE=true
  echo -e "${GREEN}  gitleaks found${NC}"
else
  echo -e "${YELLOW}  gitleaks not found (optional, skipping secret scanning)${NC}"
fi

echo ""
echo -e "${BLUE}Validating ${ENV} application manifests${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#######################################
# Step 1: YAML Syntax (yamllint)
#######################################
if [[ "$YAMLLINT_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}Step 1: Checking YAML syntax...${NC}"

  YAMLLINT_CONFIG='{extends: relaxed, rules: {line-length: disable, truthy: disable, document-start: disable, comments-indentation: disable}}'
  YAML_ERRORS=0

  # Scan values/ and apps/ directories (skip helmfile backups and charts)
  SCAN_DIRS=("$ENV_DIR/values" "$ENV_DIR/apps")
  [[ -d "$BASE_DIR/defaults" ]] && SCAN_DIRS+=("$BASE_DIR/defaults")

  for scan_dir in "${SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue
    while IFS= read -r -d '' yaml_file; do
      if ! yamllint -d "$YAMLLINT_CONFIG" "$yaml_file" >/dev/null 2>&1; then
        echo -e "${RED}  FAIL: $(relpath "$yaml_file")${NC}"
        yamllint -d "$YAMLLINT_CONFIG" "$yaml_file" 2>&1 | sed 's/^/    /' || true
        YAML_ERRORS=$((YAML_ERRORS + 1))
      fi
    done < <(find "$scan_dir" -name '*.yaml' -type f -print0)
  done

  if [[ "$YAML_ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}  All YAML files are syntactically valid${NC}"
  else
    echo -e "${RED}  $YAML_ERRORS file(s) have YAML syntax errors${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
else
  echo -e "${YELLOW}Step 1: Skipping YAML syntax check (yamllint not installed)${NC}"
  echo ""
fi

#######################################
# Step 2: Shell Script Linting
#######################################
if [[ "$SHELLCHECK_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}Step 2: Checking shell scripts...${NC}"

  SHELL_ERRORS=0
  while IFS= read -r -d '' script; do
    if shellcheck -x "$script" >/dev/null 2>&1; then
      echo -e "${GREEN}  $(basename "$script")${NC}"
    else
      echo -e "${RED}  FAIL: $(basename "$script")${NC}"
      shellcheck -x "$script" 2>&1 | sed 's/^/    /' || true
      SHELL_ERRORS=$((SHELL_ERRORS + 1))
    fi
  done < <(find "$BASE_DIR/scripts" -name '*.sh' -type f -print0 2>/dev/null)

  if [[ "$SHELL_ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}  All shell scripts pass shellcheck${NC}"
  else
    echo -e "${RED}  $SHELL_ERRORS script(s) have issues${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
else
  echo -e "${YELLOW}Step 2: Skipping shellcheck (not installed)${NC}"
  echo ""
fi

#######################################
# Step 3: Value File Reference Integrity
#######################################
echo -e "${YELLOW}Step 3: Checking value file references...${NC}"

REF_ERRORS=0

# Extract $values/ references from a YAML file (literal $values, not a shell variable)
extract_value_refs() {
  # shellcheck disable=SC2016
  grep -oE '\$values/[^ "]+' "$1" 2>/dev/null || true
}

# Find all app spec files and check their $values/ references
while IFS= read -r -d '' app_spec; do
  rel_spec=$(relpath "$app_spec")

  while IFS= read -r ref_path; do
    [[ -z "$ref_path" ]] && continue

    # Resolve $values/ to project root
    resolved="${ref_path/#\$values\//}"
    full_path="$PROJECT_ROOT/$resolved"

    if [[ ! -f "$full_path" ]]; then
      echo -e "${RED}  FAIL: $rel_spec${NC}"
      echo -e "${RED}    references: $ref_path${NC}"
      echo -e "${RED}    not found:  $resolved${NC}"
      REF_ERRORS=$((REF_ERRORS + 1))
    fi
  done < <(extract_value_refs "$app_spec")

done < <(find "$ENV_DIR/apps" -name '*.yaml' -type f -print0 2>/dev/null)

if [[ "$REF_ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}  All value file references resolve to existing files${NC}"
else
  echo -e "${RED}  $REF_ERRORS broken reference(s) found${NC}"
  VALIDATION_FAILED=true
fi
echo ""

#######################################
# Step 4: Placeholder Validation
#######################################
if [[ "$SKIP_PLACEHOLDERS" == "false" ]]; then
  echo -e "${YELLOW}Step 4: Running placeholder validation...${NC}"

  if "$SCRIPT_DIR/validate-instance.sh" "$ENV" 2>&1 | sed 's/^/  /'; then
    echo -e "${GREEN}  Placeholder validation passed${NC}"
  else
    echo -e "${RED}  Placeholder validation failed${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
else
  echo -e "${YELLOW}Step 4: Skipping placeholder validation (--skip-placeholders)${NC}"
  echo ""
fi

#######################################
# Step 5: Secret Scanning (gitleaks)
#######################################
if [[ "$GITLEAKS_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}Step 5: Scanning for secrets...${NC}"

  GITLEAKS_CONFIG="$PROJECT_ROOT/scripts/gitleaks-config.toml"
  GITLEAKS_ARGS=(detect --no-git --redact --exit-code 1)
  [[ -f "$GITLEAKS_CONFIG" ]] && GITLEAKS_ARGS+=(--config "$GITLEAKS_CONFIG")

  SCAN_FAILED=false

  # Scan env values and app specs
  for scan_dir in "$ENV_DIR/values" "$ENV_DIR/apps" "$BASE_DIR/defaults"; do
    [[ -d "$scan_dir" ]] || continue
    rel_dir="${scan_dir#"$BASE_DIR/"}"
    if gitleaks "${GITLEAKS_ARGS[@]}" --source "$scan_dir" >/dev/null 2>&1; then
      echo -e "${GREEN}  $rel_dir${NC}"
    else
      echo -e "${RED}  FAIL: $rel_dir${NC}"
      gitleaks "${GITLEAKS_ARGS[@]}" --source "$scan_dir" --verbose 2>&1 | sed 's/^/    /' || true
      SCAN_FAILED=true
    fi
  done

  if [[ "$SCAN_FAILED" == "true" ]]; then
    echo -e "${RED}  Secret scanning found potential secrets${NC}"
    VALIDATION_FAILED=true
  else
    echo -e "${GREEN}  No secrets detected${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}Step 5: Skipping secret scanning (gitleaks not installed)${NC}"
  echo ""
fi

#######################################
# Summary
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$VALIDATION_FAILED" == "true" ]]; then
  echo -e "${RED}Validation Failed${NC}"
  echo ""
  echo -e "${BLUE}Installation tips:${NC}"
  if [[ "$YAMLLINT_AVAILABLE" == "false" ]]; then
    echo -e "  ${YELLOW}Install yamllint:${NC} pip install yamllint"
  fi
  if [[ "$SHELLCHECK_AVAILABLE" == "false" ]]; then
    echo -e "  ${YELLOW}Install shellcheck:${NC} brew install shellcheck"
  fi
  if [[ "$GITLEAKS_AVAILABLE" == "false" ]]; then
    echo -e "  ${YELLOW}Install gitleaks:${NC} brew install gitleaks"
  fi
  echo ""
  exit 1
else
  echo -e "${GREEN}Validation Complete!${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  exit 0
fi
