#!/bin/bash
#######################################
# Deploy Ingress Controller
#######################################
# Deploys Kong Ingress Controller and all dependencies
# using helmfile from the management server.
#
# Usage:
#   ./deploy-ingress.sh [--skip-prerequisites]
#
# Options:
#   --skip-prerequisites  Skip cert-manager and reloader if already deployed
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

# Parse arguments
SKIP_PREREQUISITES=false
if [[ "${1:-}" == "--skip-prerequisites" ]]; then
    SKIP_PREREQUISITES=true
fi

# Set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELMFILE="${SCRIPT_DIR}/ingress-helmfile.yaml"

# Check if helmfile is installed
if ! command -v helmfile &> /dev/null; then
    error "helmfile is not installed. Please install it first:"
    error "  curl -fsSL https://raw.githubusercontent.com/helmfile/helmfile/main/scripts/get-helmfile-3.sh | bash"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
    error "kubectl is not configured. Please run:"
    error "  aws eks update-kubeconfig --region eu-central-2 --name eks-uq-dogfood-sbx-euc2"
    exit 1
fi

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Deploying Ingress Controller (Kong)"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verify helmfile exists
if [ ! -f "$HELMFILE" ]; then
    error "Helmfile not found: ${HELMFILE}"
    exit 1
fi

# Sync helm repositories
info "Syncing Helm repositories..."
helmfile -f "$HELMFILE" repos

# Check prerequisites
if [ "$SKIP_PREREQUISITES" = false ]; then
    info "Deploying prerequisites (cert-manager, reloader)..."
    helmfile -f "$HELMFILE" sync --selector name=cert-manager
    helmfile -f "$HELMFILE" sync --selector name=clusterissuer-route53-dns
    helmfile -f "$HELMFILE" sync --selector name=reloader
    
    info "Waiting for prerequisites to be ready..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=5m || true
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=reloader -n reloader --timeout=5m || true
else
    warn "Skipping prerequisites (assuming cert-manager and reloader are already deployed)"
fi

# Deploy Kong components
info "Deploying Kong Ingress Controller components..."
helmfile -f "$HELMFILE" sync --selector name!=cert-manager --selector name!=clusterissuer-route53-dns --selector name!=reloader

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Verification"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait a moment for resources to be created
sleep 5

# Check cert-manager
info "Checking cert-manager..."
if kubectl get namespace cert-manager &>/dev/null; then
    kubectl get pods -n cert-manager || warn "cert-manager pods not found"
else
    warn "cert-manager namespace not found"
fi

# Check reloader
info "Checking reloader..."
if kubectl get namespace reloader &>/dev/null; then
    kubectl get pods -n reloader || warn "reloader pods not found"
else
    warn "reloader namespace not found"
fi

# Check Kong
info "Checking Kong Ingress Controller..."
if kubectl get namespace unique &>/dev/null; then
    kubectl get pods -n unique | grep -E "kong|ingress" || warn "Kong pods not found"
    kubectl get svc -n unique | grep -E "kong|ingress" || warn "Kong services not found"
    kubectl get ingress -n unique || warn "Kong ingress resources not found"
else
    warn "unique namespace not found"
fi

echo ""
log "Deployment complete!"
info ""
info "Next steps:"
info "  1. Verify all pods are running: kubectl get pods -A | grep -E 'cert-manager|reloader|kong'"
info "  2. Check Kong Gateway: kubectl get svc -n unique kong-gateway-proxy"
info "  3. Check Ingress resources: kubectl get ingress -n unique"
info "  4. Check Gateway API: kubectl get gateway -n unique"
echo ""

