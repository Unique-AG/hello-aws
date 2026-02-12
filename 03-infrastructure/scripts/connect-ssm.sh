#!/usr/bin/env bash

# SSM Session Manager Connection Script

#
# Connects to EC2 instances via AWS Systems Manager Session Manager.
# Supports both interactive sessions and port forwarding.
#
# Usage:
#   ./connect-ssm.sh [instance-id] [options]
#
# Options:
#   -p, --port-forward    Enable port forwarding (default: 22 -> 2222)
#   -r, --remote-port     Remote port for port forwarding (default: 22)
#   -l, --local-port      Local port for port forwarding (default: 2222)
#   -m, --management      Connect to management server (auto-detects instance ID)
#   -h, --help            Show this help message
#
# Examples:
#   # Connect to management server interactively
#   ./connect-ssm.sh --management
#
#   # Connect to specific instance
#   ./connect-ssm.sh i-1234567890abcdef0
#
#   # Port forward SSH from management server
#   ./connect-ssm.sh --management --port-forward
#
#   # Port forward custom port
#   ./connect-ssm.sh i-1234567890abcdef0 -p -r 8080 -l 8080

set -euo pipefail

# Colors & Output

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()    { echo -e "${BLUE}[i]${NC} $1"; }

# Configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Default values
PORT_FORWARD=false
REMOTE_PORT=22
LOCAL_PORT=2222
MANAGEMENT_SERVER=false
INSTANCE_ID=""

# Functions

show_help() {
  cat << EOF
SSM Session Manager Connection Script

Usage:
  $0 [instance-id] [options]

Options:
  -p, --port-forward        Enable port forwarding (default: 22 -> 2222)
  -r, --remote-port PORT    Remote port for port forwarding (default: 22)
  -l, --local-port PORT     Local port for port forwarding (default: 2222)
  -m, --management          Connect to management server (auto-detects instance ID)
  -h, --help                Show this help message

Examples:
  # Connect to management server interactively
  $0 --management

  # Connect to specific instance
  $0 i-1234567890abcdef0

  # Port forward SSH from management server
  $0 --management --port-forward

  # Port forward custom port
  $0 i-1234567890abcdef0 -p -r 8080 -l 8080

Prerequisites:
  - AWS CLI installed and configured
  - Session Manager plugin installed
    macOS: brew install --cask session-manager-plugin
    Linux: See https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
}

# Check prerequisites
check_prerequisites() {
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI first."
  fi

  # Check AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
  fi

  # Check Session Manager plugin
  if ! command -v session-manager-plugin &> /dev/null; then
    warn "Session Manager plugin not found."
    warn "Install it:"
    warn "  macOS: brew install --cask session-manager-plugin"
    warn "  Linux: See AWS documentation"
    error "Please install the Session Manager plugin first."
  fi

  log "Prerequisites check passed"
}

# Get management server instance ID from Terraform state
get_management_server_id() {
  info "Attempting to get management server instance ID from Terraform state..."

  # Try to get from Terraform state
  if command -v terraform &> /dev/null && [ -d "${TERRAFORM_DIR}" ]; then
    cd "${TERRAFORM_DIR}"
    
    # Try to get instance ID from state
    INSTANCE_ID=$(terraform output -raw management_server_instance_id 2>/dev/null || echo "")
    
    if [ -n "${INSTANCE_ID}" ] && [ "${INSTANCE_ID}" != "null" ]; then
      log "Found management server instance ID: ${INSTANCE_ID}"
      return 0
    fi
  fi

  # Fallback: Try to find instance by tag
  info "Trying to find management server by tags..."
  
  # Get current AWS region
  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
    warn "AWS region not set, defaulting to ${AWS_REGION}"
  fi

  # Try to find instance with management server tag
  INSTANCE_ID=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=*management-server" \
      "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "")

  if [ -n "${INSTANCE_ID}" ] && [ "${INSTANCE_ID}" != "None" ]; then
    log "Found management server instance ID: ${INSTANCE_ID}"
    return 0
  fi

  error "Could not find management server instance ID. Please provide it manually or ensure Terraform state is available."
}

# Start instance if stopped
ensure_instance_running() {
  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
  fi

  # Check instance state
  INSTANCE_STATE=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

  if [ "${INSTANCE_STATE}" = "running" ]; then
    log "Instance ${INSTANCE_ID} is running"
    return 0
  elif [ "${INSTANCE_STATE}" = "stopped" ]; then
    info "Instance ${INSTANCE_ID} is stopped. Starting it..."
    aws ec2 start-instances --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" > /dev/null
    info "Waiting for instance to be running..."
    aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"
    log "Instance ${INSTANCE_ID} is now running"
  elif [ "${INSTANCE_STATE}" = "pending" ]; then
    info "Instance ${INSTANCE_ID} is starting. Waiting..."
    aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"
    log "Instance ${INSTANCE_ID} is now running"
  else
    error "Instance ${INSTANCE_ID} is in state '${INSTANCE_STATE}'. Cannot connect."
  fi
}

# Wait for SSM connectivity
wait_for_ssm() {
  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
  fi

  local max_attempts=12
  local attempt=1
  local wait_seconds=10

  info "Waiting for SSM agent to connect..."
  
  while [ $attempt -le $max_attempts ]; do
    if aws ssm describe-instance-information \
      --region "${AWS_REGION}" \
      --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null | grep -q "Online"; then
      log "SSM agent is online"
      return 0
    fi
    info "Attempt ${attempt}/${max_attempts}: SSM agent not ready, waiting ${wait_seconds}s..."
    sleep $wait_seconds
    ((attempt++))
  done

  return 1
}

# Verify instance is accessible via SSM
verify_instance() {
  info "Verifying instance ${INSTANCE_ID} is accessible via SSM..."

  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
  fi

  # Check if instance is in SSM and online
  local ping_status
  ping_status=$(aws ssm describe-instance-information \
    --region "${AWS_REGION}" \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || echo "")

  if [ "${ping_status}" = "Online" ]; then
    log "Instance ${INSTANCE_ID} is connected to SSM"
    return 0
  fi

  # Try waiting for SSM to connect
  if wait_for_ssm; then
    return 0
  fi

  error "Instance ${INSTANCE_ID} is not accessible via SSM. Ensure:"
  error "  1. Instance has SSM agent installed and running"
  error "  2. Instance has IAM role with AmazonSSMManagedInstanceCore policy"
  error "  3. SSM VPC endpoints are configured (if in private subnet)"
}

# Start interactive session
start_interactive_session() {
  info "Starting interactive Session Manager session to ${INSTANCE_ID}..."
  info "Type 'exit' to end the session"
  echo ""

  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
  fi

  aws ssm start-session \
    --target "${INSTANCE_ID}" \
    --region "${AWS_REGION}"
}

# Start port forwarding session
start_port_forwarding() {
  info "Starting port forwarding session..."
  info "Forwarding remote port ${REMOTE_PORT} to local port ${LOCAL_PORT}"
  echo ""

  AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="eu-central-2"
  fi

  # Start SSM session in background and monitor port
  (
    aws ssm start-session \
      --target "${INSTANCE_ID}" \
      --region "${AWS_REGION}" \
      --document-name AWS-StartPortForwardingSession \
      --parameters "{\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" > /dev/null 2>&1 &
    SSM_PID=$!
    
    # Wait for port to become available (max 30 seconds)
    info "Waiting for port forwarding to establish..."
    local max_wait=30
    local waited=0
    while [ ${waited} -lt ${max_wait} ]; do
      if lsof -ti:"${LOCAL_PORT}" > /dev/null 2>&1; then
        echo ""
        log "Port forwarding is now ACTIVE on port ${LOCAL_PORT}"
        if [ "${REMOTE_PORT}" = "22" ]; then
          info "You can now SSH to:"
          info "  ssh -p ${LOCAL_PORT} ec2-user@localhost"
          info "Or connect via Remote-SSH using 'management-server'"
        fi
        echo ""
        info "Port forwarding session is running. Press Ctrl+C to stop."
        wait ${SSM_PID}
        return 0
      fi
      sleep 1
      waited=$((waited + 1))
      if [ $((waited % 5)) -eq 0 ]; then
        info "Still waiting... (${waited}s/${max_wait}s)"
      fi
    done
    
    warn "Port forwarding did not establish within ${max_wait} seconds"
    warn "The SSM session may be stuck. Try running:"
    warn "  ./03-infrastructure/scripts/port-forward-health.sh --cleanup-only"
    kill ${SSM_PID} 2>/dev/null
    return 1
  ) &
  
  MONITOR_PID=$!
  
  # Trap Ctrl+C to clean up
  trap "kill ${MONITOR_PID} 2>/dev/null; pkill -f 'aws ssm start-session.*${LOCAL_PORT}' 2>/dev/null; exit" INT TERM
  
  # Wait for the monitor process
  wait ${MONITOR_PID}
  local exit_code=$?
  
  # Clean up trap
  trap - INT TERM
  
  if [ "${exit_code}" -ne 0 ]; then
    error "Port forwarding failed to establish"
    return 1
  fi
}

# Parse Arguments

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--port-forward)
      PORT_FORWARD=true
      shift
      ;;
    -r|--remote-port)
      REMOTE_PORT="$2"
      shift 2
      ;;
    -l|--local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    -m|--management)
      MANAGEMENT_SERVER=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    i-*)
      INSTANCE_ID="$1"
      shift
      ;;
    *)
      error "Unknown option: $1. Use --help for usage information."
      ;;
  esac
done

# Main

# Check prerequisites
check_prerequisites

# Get instance ID
if [ "${MANAGEMENT_SERVER}" = true ]; then
  get_management_server_id
elif [ -z "${INSTANCE_ID}" ]; then
  error "Please provide an instance ID or use --management flag. Use --help for usage information."
fi

# Ensure instance is running
ensure_instance_running

# Verify instance
verify_instance

# Start session
if [ "${PORT_FORWARD}" = true ]; then
  start_port_forwarding
else
  start_interactive_session
fi

