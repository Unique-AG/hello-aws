#!/bin/bash
#######################################
# Deploy System Application
#######################################
# Deploys a single system application to the EKS cluster
# from the management server.
#
# Usage:
#   ./deploy-system-app.sh <app-name>
#
# Example:
#   ./deploy-system-app.sh cert-manager
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

# Check if app name is provided
APP_NAME="${1:-}"
if [ -z "$APP_NAME" ]; then
    error "Usage: $0 <app-name>"
    error "Available apps: cert-manager, external-secrets, reloader, aks-extensions, rabbitmq-operator, eck, elasticsearch, kong, zitadel, argo"
    exit 1
fi

# Set paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="${SCRIPT_DIR}/apps/system"
VALUES_DIR="${SCRIPT_DIR}/../values"
WORKSPACE_DIR="${HOME:-/home/ec2-user}/workspace"

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
    error "kubectl is not configured. Please run: aws eks update-kubeconfig --region eu-central-2 --name eks-uq-dogfood-sbx-euc2"
    exit 1
fi

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Deploying: ${APP_NAME}"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if app manifest exists
APP_MANIFEST="${APPS_DIR}/${APP_NAME}.yaml"
if [ ! -f "$APP_MANIFEST" ]; then
    error "Application manifest not found: ${APP_MANIFEST}"
    error "Available apps:"
    ls -1 "${APPS_DIR}"/*.yaml | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/  - /'
    exit 1
fi

# Check if this is an ArgoCD Application
if grep -q "kind: Application" "$APP_MANIFEST" 2>/dev/null; then
    info "Detected ArgoCD Application manifest"
    
    # Check if ArgoCD is running
    if ! kubectl get namespace argocd &>/dev/null; then
        warn "ArgoCD namespace not found. This is an ArgoCD Application manifest."
        warn "You have two options:"
        warn "  1. Deploy ArgoCD first (recommended)"
        warn "  2. Deploy this application manually using Helm"
        echo ""
        read -p "Continue with ArgoCD Application deployment? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Deploy ArgoCD Application
    info "Applying ArgoCD Application manifest..."
    kubectl apply -f "$APP_MANIFEST"
    
    # Get namespace from manifest (if specified)
    NAMESPACE=$(grep -A 5 "spec:" "$APP_MANIFEST" | grep "namespace:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    
    if [ -n "$NAMESPACE" ]; then
        info "Waiting for namespace: ${NAMESPACE}"
        kubectl wait --for=condition=Ready namespace/${NAMESPACE} --timeout=60s || true
    fi
    
    log "ArgoCD Application '${APP_NAME}' deployed"
    info "Monitor status with: kubectl get application ${APP_NAME} -n argocd"
    
else
    # This is a regular Kubernetes manifest
    info "Applying Kubernetes manifest..."
    kubectl apply -f "$APP_MANIFEST"
    log "Application '${APP_NAME}' deployed"
fi

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Verification"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait a moment for resources to be created
sleep 2

# Check if it's an ArgoCD Application
if grep -q "kind: Application" "$APP_MANIFEST" 2>/dev/null; then
    info "Checking ArgoCD Application status..."
    kubectl get application "${APP_NAME}" -n argocd 2>/dev/null || warn "Application not found in argocd namespace (may need to check other namespaces)"
else
    # Try to determine namespace and show resources
    info "Checking deployed resources..."
    
    # Common namespaces for system apps
    for NS in cert-manager external-secrets reloader kube-system unique default; do
        if kubectl get namespace "$NS" &>/dev/null; then
            RESOURCES=$(kubectl get all -n "$NS" 2>/dev/null | grep -i "${APP_NAME}" || true)
            if [ -n "$RESOURCES" ]; then
                info "Resources in namespace '${NS}':"
                kubectl get all -n "$NS" | grep -i "${APP_NAME}" || true
                break
            fi
        fi
    done
fi

echo ""
log "Deployment complete for: ${APP_NAME}"
info ""
info "Next steps:"
info "  1. Wait for pods to be ready: kubectl get pods -n <namespace>"
info "  2. Check logs if issues: kubectl logs -n <namespace> <pod-name>"
info "  3. Deploy next application when ready"
echo ""

