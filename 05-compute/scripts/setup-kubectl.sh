#!/usr/bin/env bash
#######################################
# EKS kubectl Setup Script
#######################################
#
# Configures kubectl to access the EKS cluster.
# Installs eksctl and kubectl if not present.
#
# Usage:
#   ./setup-kubectl.sh [options]
#
# Options:
#   -c, --cluster NAME    Cluster name (auto-detects from Terraform if not provided)
#   -r, --region REGION   AWS region (default: eu-central-2)
#   -i, --install         Install kubectl and eksctl if not present
#   -h, --help            Show this help message
#
# Examples:
#   # Auto-configure from Terraform state
#   ./setup-kubectl.sh
#
#   # Configure specific cluster
#   ./setup-kubectl.sh --cluster eks-uq-acme-sbx-euc2 --region eu-central-2
#
#   # Install tools and configure
#   ./setup-kubectl.sh --install
#######################################

set -euo pipefail

#######################################
# Colors & Output
#######################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()    { echo -e "${BLUE}[i]${NC} $1"; }

#######################################
# Configuration
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Default values
CLUSTER_NAME=""
AWS_REGION="${AWS_REGION:-eu-central-2}"
INSTALL_TOOLS=false

#######################################
# Functions
#######################################

show_help() {
  cat << EOF
${BOLD}EKS kubectl Setup Script${NC}

${BOLD}Usage:${NC}
  $0 [options]

${BOLD}Options:${NC}
  -c, --cluster NAME    Cluster name (auto-detects from Terraform if not provided)
  -r, --region REGION   AWS region (default: eu-central-2)
  -i, --install         Install kubectl and eksctl if not present
  -h, --help            Show this help message

${BOLD}Examples:${NC}
  # Auto-configure from Terraform state
  $0

  # Configure specific cluster
  $0 --cluster eks-uq-acme-sbx-euc2 --region eu-central-2

  # Install tools and configure
  $0 --install

${BOLD}Prerequisites:${NC}
  - AWS CLI installed and configured
  - kubectl (will install if --install flag is used)
  - eksctl (optional, will install if --install flag is used)
EOF
}

# Detect OS
detect_os() {
  case "$(uname -s)" in
    Darwin*)  OS="macos";;
    Linux*)   OS="linux";;
    *)        OS="unknown";;
  esac
  
  case "$(uname -m)" in
    x86_64)   ARCH="amd64";;
    arm64)    ARCH="arm64";;
    aarch64)  ARCH="arm64";;
    *)        ARCH="amd64";;
  esac
}

# Install kubectl
install_kubectl() {
  if command -v kubectl &> /dev/null; then
    log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    return 0
  fi

  info "Installing kubectl..."
  
  detect_os
  
  if [ "$OS" = "macos" ]; then
    if command -v brew &> /dev/null; then
      brew install kubectl
    else
      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/${ARCH}/kubectl"
      chmod +x kubectl
      sudo mv kubectl /usr/local/bin/
    fi
  elif [ "$OS" = "linux" ]; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  else
    error "Unsupported OS. Please install kubectl manually."
  fi
  
  log "kubectl installed successfully"
}

# Install eksctl
install_eksctl() {
  if command -v eksctl &> /dev/null; then
    log "eksctl already installed: $(eksctl version)"
    return 0
  fi

  info "Installing eksctl..."
  
  detect_os
  
  if [ "$OS" = "macos" ]; then
    if command -v brew &> /dev/null; then
      brew tap weaveworks/tap
      brew install weaveworks/tap/eksctl
    else
      curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Darwin_${ARCH}.tar.gz" | tar xz -C /tmp
      sudo mv /tmp/eksctl /usr/local/bin
    fi
  elif [ "$OS" = "linux" ]; then
    curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${ARCH}.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
  else
    error "Unsupported OS. Please install eksctl manually."
  fi
  
  log "eksctl installed successfully"
}

# Install AWS CLI Session Manager plugin
install_session_manager_plugin() {
  if command -v session-manager-plugin &> /dev/null; then
    log "Session Manager plugin already installed"
    return 0
  fi

  info "Installing AWS Session Manager plugin..."
  
  detect_os
  
  if [ "$OS" = "macos" ]; then
    if command -v brew &> /dev/null; then
      brew install --cask session-manager-plugin
    else
      warn "Please install session-manager-plugin manually from:"
      warn "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    fi
  elif [ "$OS" = "linux" ]; then
    warn "Please install session-manager-plugin manually from:"
    warn "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  fi
}

# Check prerequisites
check_prerequisites() {
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI first."
  fi

  # Check AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE."
  fi

  log "AWS CLI configured for account: $(aws sts get-caller-identity --query Account --output text)"
}

# Get cluster name from Terraform state
get_cluster_from_terraform() {
  info "Getting cluster name from Terraform state..."

  if [ ! -d "${TERRAFORM_DIR}" ]; then
    warn "Terraform directory not found at ${TERRAFORM_DIR}"
    return 1
  fi

  cd "${TERRAFORM_DIR}"
  
  # Try to get cluster name from Terraform output
  CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
  
  if [ -n "${CLUSTER_NAME}" ] && [ "${CLUSTER_NAME}" != "null" ]; then
    log "Found cluster name from Terraform: ${CLUSTER_NAME}"
    return 0
  fi

  return 1
}

# Get cluster name from AWS
get_cluster_from_aws() {
  info "Listing EKS clusters in ${AWS_REGION}..."
  
  CLUSTERS=$(aws eks list-clusters --region "${AWS_REGION}" --query 'clusters[]' --output text 2>/dev/null || echo "")
  
  if [ -z "${CLUSTERS}" ]; then
    error "No EKS clusters found in ${AWS_REGION}"
  fi

  CLUSTER_COUNT=$(echo "${CLUSTERS}" | wc -w | tr -d ' ')
  
  if [ "${CLUSTER_COUNT}" -eq 1 ]; then
    CLUSTER_NAME="${CLUSTERS}"
    log "Found single cluster: ${CLUSTER_NAME}"
    return 0
  fi

  echo ""
  info "Multiple clusters found. Please select one:"
  select CLUSTER_NAME in ${CLUSTERS}; do
    if [ -n "${CLUSTER_NAME}" ]; then
      log "Selected cluster: ${CLUSTER_NAME}"
      break
    fi
  done
}

# Configure kubeconfig
configure_kubeconfig() {
  info "Configuring kubectl for cluster ${CLUSTER_NAME}..."
  
  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}"
  
  log "kubectl configured successfully"
  
  # Verify connection
  info "Verifying cluster connection..."
  if kubectl cluster-info &>/dev/null; then
    log "Successfully connected to cluster"
    echo ""
    kubectl cluster-info
  else
    warn "Could not verify cluster connection. This may be due to:"
    warn "  - Cluster is still initializing"
    warn "  - Network restrictions (VPN required?)"
    warn "  - IAM permissions"
  fi
}

# Show cluster info
show_cluster_info() {
  echo ""
  echo -e "${BOLD}Cluster Information:${NC}"
  echo "  Name:     ${CLUSTER_NAME}"
  echo "  Region:   ${AWS_REGION}"
  echo ""
  echo -e "${BOLD}Useful commands:${NC}"
  echo "  kubectl get nodes                    # List nodes"
  echo "  kubectl get pods -A                  # List all pods"
  echo "  kubectl get namespaces               # List namespaces"
  echo "  eksctl get nodegroup --cluster ${CLUSTER_NAME} --region ${AWS_REGION}"
  echo ""
}

#######################################
# Parse Arguments
#######################################

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--cluster)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -r|--region)
      AWS_REGION="$2"
      shift 2
      ;;
    -i|--install)
      INSTALL_TOOLS=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1. Use --help for usage information."
      ;;
  esac
done

#######################################
# Main
#######################################

echo -e "${BOLD}EKS kubectl Setup${NC}"
echo ""

# Install tools if requested
if [ "${INSTALL_TOOLS}" = true ]; then
  install_kubectl
  install_eksctl
  install_session_manager_plugin
  echo ""
fi

# Check prerequisites
check_prerequisites

# Get cluster name
if [ -z "${CLUSTER_NAME}" ]; then
  # Try Terraform first, then AWS
  if ! get_cluster_from_terraform; then
    get_cluster_from_aws
  fi
fi

# Configure kubeconfig
configure_kubeconfig

# Show info
show_cluster_info

log "Setup complete!"
