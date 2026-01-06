#!/bin/bash
#######################################
# Deploy System Applications Sequence (Incremental)
#######################################
# Deploys system applications to EKS cluster incrementally:
# Phase 1: Foundation
#   - cert-manager (TLS certificate management)
#   - external-secrets (Secrets management)
#   - reloader (ConfigMap/Secret reloader)
# Phase 2: Kong (depends on cert-manager + reloader)
#   - kong (Ingress Controller)
# Phase 3: Zitadel (depends on external-secrets + kong)
#   - zitadel (Identity Provider)
#
# Features:
#   - Incremental: Deploy → Validate → Continue
#   - Resumable: Skips already deployed and healthy components
#   - Validates dependencies before proceeding
#
# Usage:
#   ./deploy-system-apps-sequence.sh [--skip-validation]
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
step()  { echo -e "${CYAN}[→]${NC} $1"; }

# Parse arguments
SKIP_VALIDATION=false
if [[ "${1:-}" == "--skip-validation" ]]; then
    SKIP_VALIDATION=true
fi

# Set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Configure environment
export AWS_REGION=eu-central-2
export KUBECONFIG=${HOME}/.kube/config

#######################################
# Validation Functions
#######################################

# Check if cert-manager is deployed and healthy
validate_cert_manager() {
    local namespace="cert-manager"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=cert-manager --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ready_pods" -lt 1 ]; then
        return 1
    fi
    
    # Check if ClusterIssuer exists (if cert-manager is fully functional)
    if ! kubectl get clusterissuer letsencrypt-route53-dns &>/dev/null 2>&1; then
        warn "cert-manager is running but ClusterIssuer 'letsencrypt-route53-dns' not found yet"
        return 1
    fi
    
    return 0
}

# Check if external-secrets is deployed and healthy
validate_external_secrets() {
    local namespace="external-secrets-system"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ready_pods" -lt 1 ]; then
        return 1
    fi
    
    # Check if ClusterSecretStore exists
    if ! kubectl get clustersecretstore aws-secrets-manager &>/dev/null 2>&1; then
        warn "External Secrets Operator is running but ClusterSecretStore 'aws-secrets-manager' not found yet"
        return 1
    fi
    
    return 0
}

# Check if reloader is deployed and healthy
validate_reloader() {
    local namespace="reloader"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods=$(kubectl get pods -n "$namespace" -l app=reloader --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ready_pods" -lt 1 ]; then
        return 1
    fi
    
    return 0
}

# Check if Kong is deployed and healthy
validate_kong() {
    local namespace="unique"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 1
    fi
    
    # Check if Kong pods are ready
    local ready_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=kong --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ready_pods" -lt 1 ]; then
        return 1
    fi
    
    # Check if Kong Gateway exists
    if ! kubectl get gateway kong -n "$namespace" &>/dev/null 2>&1; then
        warn "Kong pods are running but Gateway 'kong' not found yet"
        return 1
    fi
    
    return 0
}

# Check if Zitadel is deployed and healthy
validate_zitadel() {
    local namespace="zitadel"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=zitadel --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ready_pods" -lt 1 ]; then
        return 1
    fi
    
    return 0
}

# Wait for pods to be ready with timeout
wait_for_pods() {
    local namespace="$1"
    local selector="$2"
    local timeout="${3:-300}"
    local label="${4:-}"
    
    info "Waiting for pods to be ready (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=ready pod -l "$selector" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log "${label:-Pods} are ready"
        return 0
    else
        warn "${label:-Pods} may still be starting or have issues"
        kubectl get pods -n "$namespace" -l "$selector" || true
        return 1
    fi
}

# Deploy and validate a component
deploy_and_validate() {
    local app_name="$1"
    local validation_func="$2"
    local namespace="$3"
    local selector="$4"
    local label="$5"
    local step_num="$6"
    local total_steps="$7"
    
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    step "Step ${step_num}/${total_steps}: ${label}"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Check if already deployed and healthy
    if $validation_func; then
        log "${label} is already deployed and healthy - skipping"
        kubectl get pods -n "$namespace" -l "$selector" 2>/dev/null || true
        echo ""
        return 0
    fi
    
    # Deploy
    step "Deploying ${app_name}..."
    if ! ./deploy-system-app.sh "$app_name"; then
        error "Failed to deploy ${app_name}"
    fi
    
    # Wait for pods
    sleep 5
    wait_for_pods "$namespace" "$selector" 300 "$label"
    
    # Validate (if not skipped)
    if [ "$SKIP_VALIDATION" = false ]; then
        step "Validating ${label}..."
        local max_attempts=12
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if $validation_func; then
                log "${label} validation passed"
                echo ""
                return 0
            fi
            
            if [ $attempt -lt $max_attempts ]; then
                info "Validation attempt ${attempt}/${max_attempts} - waiting 10s before retry..."
                sleep 10
            fi
            attempt=$((attempt + 1))
        done
        
        warn "${label} validation incomplete - component may still be initializing"
        warn "You can continue, but some features may not be available yet"
    fi
    
    echo ""
    return 0
}

#######################################
# Main Deployment Sequence
#######################################

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Configuring kubectl for EKS cluster"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Configure kubectl
if ! aws eks update-kubeconfig --region ${AWS_REGION} --name eks-uq-dogfood-sbx-euc2; then
    error "Failed to configure kubectl"
fi

if ! kubectl cluster-info &>/dev/null; then
    error "kubectl cluster-info failed - check cluster connectivity"
fi

log "kubectl configured successfully"
echo ""

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Starting Incremental Deployment Sequence"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$SKIP_VALIDATION" = true ]; then
    warn "Validation is disabled - components will be deployed but not validated"
fi
echo ""

#######################################
# Phase 1: Foundation Components
#######################################

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Phase 1: Foundation Components"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. cert-manager
deploy_and_validate \
    "cert-manager" \
    "validate_cert_manager" \
    "cert-manager" \
    "app.kubernetes.io/name=cert-manager" \
    "cert-manager" \
    "1" \
    "5"

# 2. external-secrets
deploy_and_validate \
    "external-secrets" \
    "validate_external_secrets" \
    "external-secrets-system" \
    "app.kubernetes.io/name=external-secrets" \
    "External Secrets Operator" \
    "2" \
    "5"

# 3. reloader
deploy_and_validate \
    "reloader" \
    "validate_reloader" \
    "reloader" \
    "app=reloader" \
    "Reloader" \
    "3" \
    "5"

#######################################
# Phase 2: Kong (depends on cert-manager + reloader)
#######################################

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Phase 2: Kong Ingress Controller"
info "Dependencies: cert-manager ✓, reloader ✓"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate dependencies
step "Validating dependencies..."
if ! validate_cert_manager; then
    error "Dependency check failed: cert-manager is not ready"
fi
if ! validate_reloader; then
    error "Dependency check failed: reloader is not ready"
fi
log "All dependencies satisfied"
echo ""

# 4. kong
deploy_and_validate \
    "kong" \
    "validate_kong" \
    "unique" \
    "app.kubernetes.io/name=kong" \
    "Kong Ingress Controller" \
    "4" \
    "5"

#######################################
# Phase 3: Zitadel (depends on external-secrets + kong)
#######################################

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Phase 3: Zitadel Identity Provider"
info "Dependencies: external-secrets ✓, kong ✓"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate dependencies
step "Validating dependencies..."
if ! validate_external_secrets; then
    error "Dependency check failed: External Secrets Operator is not ready"
fi
if ! validate_kong; then
    error "Dependency check failed: Kong is not ready"
fi
log "All dependencies satisfied"
echo ""

# 5. zitadel
deploy_and_validate \
    "zitadel" \
    "validate_zitadel" \
    "zitadel" \
    "app.kubernetes.io/name=zitadel" \
    "Zitadel Identity Provider" \
    "5" \
    "5"

#######################################
# Final Verification
#######################################

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Final Verification"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

info "Checking all deployed applications..."
echo ""

# Check each component
components=(
    "cert-manager:cert-manager:app.kubernetes.io/name=cert-manager"
    "external-secrets:external-secrets-system:app.kubernetes.io/name=external-secrets"
    "reloader:reloader:app=reloader"
    "kong:unique:app.kubernetes.io/name=kong"
    "zitadel:zitadel:app.kubernetes.io/name=zitadel"
)

all_healthy=true
for component in "${components[@]}"; do
    IFS=':' read -r name namespace selector <<< "$component"
    if kubectl get pods -n "$namespace" -l "$selector" &>/dev/null; then
        local ready=$(kubectl get pods -n "$namespace" -l "$selector" --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        local total=$(kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$ready" -gt 0 ] && [ "$ready" -eq "$total" ]; then
            log "${name}: ${ready}/${total} pods running"
        else
            warn "${name}: ${ready}/${total} pods running (may still be initializing)"
            all_healthy=false
        fi
    else
        warn "${name}: No pods found"
        all_healthy=false
    fi
done

echo ""
if [ "$all_healthy" = true ]; then
    log "Deployment sequence complete! All components are healthy."
else
    warn "Deployment sequence complete, but some components may still be initializing."
fi

info ""
info "Summary:"
info "  ✓ cert-manager - cert-manager namespace"
info "  ✓ External Secrets Operator - external-secrets-system namespace"
info "  ✓ Reloader - reloader namespace"
info "  ✓ Kong Ingress Controller - unique namespace"
info "  ✓ Zitadel Identity Provider - zitadel namespace"
echo ""
info "Next steps:"
info "  - Monitor pods: kubectl get pods -A | grep -E 'cert-manager|external-secrets|reloader|kong|zitadel'"
info "  - Check logs: kubectl logs -n <namespace> <pod-name>"
info "  - Verify Kong Gateway: kubectl get gateway kong -n unique"
info "  - Verify Zitadel HTTPRoute: kubectl get httproute zitadel -n unique"
echo ""
