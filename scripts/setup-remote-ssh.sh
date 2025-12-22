#!/usr/bin/env bash
#######################################
# Setup Remote SSH for Management Server
#######################################
# Automates the setup of Remote-SSH connection to the management server
# This script:
# 1. Sets up SSH keys on the management server
# 2. Configures SSH config for Remote-SSH
# 3. Optionally starts port forwarding
# 4. Provides connection instructions
#
# Usage:
#   ./scripts/setup-remote-ssh.sh [options]
#
# Options:
#   --skip-ssh-keys      Skip SSH key setup (if already done)
#   --skip-ssh-config    Skip SSH config setup (if already done)
#   --start-port-forward Start port forwarding in background
#   --help               Show this help message
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}==>${NC} ${BOLD}$1${NC}\n"; }

# Options
SKIP_SSH_KEYS=false
SKIP_SSH_CONFIG=false
START_PORT_FORWARD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-ssh-keys)
      SKIP_SSH_KEYS=true
      shift
      ;;
    --skip-ssh-config)
      SKIP_SSH_CONFIG=true
      shift
      ;;
    --start-port-forward)
      START_PORT_FORWARD=true
      shift
      ;;
    --help)
      cat << EOF
${BOLD}Setup Remote SSH for Management Server${NC}

${BOLD}Usage:${NC}
  $0 [options]

${BOLD}Options:${NC}
  --skip-ssh-keys      Skip SSH key setup (if already done)
  --skip-ssh-config    Skip SSH config setup (if already done)
  --start-port-forward Start port forwarding in background
  --help               Show this help message

${BOLD}What this script does:${NC}
  1. Sets up SSH keys on the management server via SSM
  2. Configures ~/.ssh/config for Remote-SSH
  3. Optionally starts port forwarding in background
  4. Provides instructions for connecting via Remote-SSH

${BOLD}Prerequisites:${NC}
  - AWS CLI installed and configured
  - Session Manager plugin installed
  - Terraform state available (for instance ID)
EOF
      exit 0
      ;;
    *)
      error "Unknown option: $1. Use --help for usage information."
      ;;
  esac
done

#######################################
# Step 1: Check Prerequisites
#######################################

step "Checking Prerequisites"

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
  error "Please install the Session Manager plugin first."
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
  error "Terraform not found. Please install Terraform first."
fi

log "All prerequisites met"

#######################################
# Step 2: Get Instance ID
#######################################

step "Getting Management Server Instance ID"

INSTANCE_ID=$(cd "${PROJECT_ROOT}/03-infrastructure/terraform" && terraform output -raw management_server_instance_id 2>/dev/null || echo "")
if [ -z "$INSTANCE_ID" ]; then
  error "Could not get instance ID from Terraform. Ensure Terraform has been applied."
fi

log "Found management server: ${INSTANCE_ID}"

# Verify instance is accessible via SSM
AWS_REGION="eu-central-2"
PING_STATUS=$(aws ssm describe-instance-information \
  --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "Unknown")

if [ "$PING_STATUS" != "Online" ]; then
  warn "Instance SSM status: ${PING_STATUS}"
  warn "Instance may not be accessible via SSM yet."
  info "Waiting for SSM agent to come online..."
  
  MAX_WAIT=60
  WAITED=0
  while [ $WAITED -lt $MAX_WAIT ]; do
    PING_STATUS=$(aws ssm describe-instance-information \
      --region "$AWS_REGION" \
      --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || echo "Unknown")
    
    if [ "$PING_STATUS" = "Online" ]; then
      log "SSM agent is now online"
      break
    fi
    
    info "Waiting for SSM... (${WAITED}s/${MAX_WAIT}s)"
    sleep 5
    WAITED=$((WAITED + 5))
  done
  
  if [ "$PING_STATUS" != "Online" ]; then
    error "Instance is not accessible via SSM. Status: ${PING_STATUS}"
    error "Ensure:"
    error "  1. Instance has SSM agent installed and running"
    error "  2. Instance has IAM role with AmazonSSMManagedInstanceCore policy"
    error "  3. SSM VPC endpoints are configured (if in private subnet)"
  fi
else
  log "Instance is accessible via SSM"
fi

#######################################
# Step 3: Setup SSH Keys
#######################################

if [ "$SKIP_SSH_KEYS" = false ]; then
  step "Setting up SSH Keys on Management Server"
  
  # Use the existing setup-ssh-keys.sh script if available
  SSH_KEYS_SCRIPT="${SCRIPT_DIR}/setup-ssh-keys.sh"
  SSH_KEYS_SETUP_SUCCESS=false
  
  if [ -f "$SSH_KEYS_SCRIPT" ]; then
    info "Using existing setup-ssh-keys.sh script"
    if "$SSH_KEYS_SCRIPT"; then
      log "SSH keys set up successfully via setup-ssh-keys.sh"
      SSH_KEYS_SETUP_SUCCESS=true
    else
      warn "setup-ssh-keys.sh failed, falling back to inline implementation"
    fi
  fi
  
  if [ "$SSH_KEYS_SETUP_SUCCESS" = false ]; then
    # Fallback: inline SSH key setup
    info "Setting up SSH keys via SSM..."
    
    # Check if we have a local SSH key
    LOCAL_SSH_KEY=""
    if [ -f ~/.ssh/id_ed25519.pub ]; then
      LOCAL_SSH_KEY="ed25519"
    elif [ -f ~/.ssh/id_rsa.pub ]; then
      LOCAL_SSH_KEY="rsa"
    elif [ -f ~/.ssh/id_ecdsa.pub ]; then
      LOCAL_SSH_KEY="ecdsa"
    fi
    
    if [ -n "$LOCAL_SSH_KEY" ]; then
      info "Found local SSH key: id_${LOCAL_SSH_KEY}.pub"
      PUB_KEY=$(cat ~/.ssh/id_${LOCAL_SSH_KEY}.pub)
    else
      warn "No local SSH key found. Will generate one on the server."
      PUB_KEY=""
    fi
    
    # Commands to set up SSH for ec2-user
    # Note: SSM commands may run as ssm-user or root, so we explicitly target ec2-user
    SSH_SETUP_COMMANDS=(
      "mkdir -p /home/ec2-user/.ssh"
      "chmod 700 /home/ec2-user/.ssh"
      "chown ec2-user:ec2-user /home/ec2-user/.ssh"
    )
    
    if [ -n "$PUB_KEY" ]; then
      # Add existing public key
      SSH_SETUP_COMMANDS+=("echo '${PUB_KEY}' >> /home/ec2-user/.ssh/authorized_keys")
      SSH_SETUP_COMMANDS+=("chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys")
      info "Will add your existing public key"
    else
      # Generate new key pair for ec2-user
      SSH_SETUP_COMMANDS+=("if [ ! -f /home/ec2-user/.ssh/id_ed25519 ]; then sudo -u ec2-user ssh-keygen -t ed25519 -f /home/ec2-user/.ssh/id_ed25519 -N '' -C 'management-server' 2>&1; fi")
      SSH_SETUP_COMMANDS+=("cat /home/ec2-user/.ssh/id_ed25519.pub >> /home/ec2-user/.ssh/authorized_keys 2>/dev/null || true")
      SSH_SETUP_COMMANDS+=("chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys")
      info "Will generate a new SSH key pair"
    fi
    
    SSH_SETUP_COMMANDS+=("chmod 600 /home/ec2-user/.ssh/authorized_keys")
    SSH_SETUP_COMMANDS+=("echo 'SSH keys set up successfully for ec2-user'")
    
    # Build JSON array of commands
    if command -v jq &> /dev/null; then
      # Use jq to build JSON array
      COMMANDS_JSON=$(printf '%s\n' "${SSH_SETUP_COMMANDS[@]}" | jq -R . | jq -s .)
    else
      # Build JSON array manually
      COMMANDS_JSON="["
      FIRST=true
      for cmd in "${SSH_SETUP_COMMANDS[@]}"; do
        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          COMMANDS_JSON="${COMMANDS_JSON},"
        fi
        # Escape the command for JSON
        ESCAPED_CMD=$(echo "$cmd" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        COMMANDS_JSON="${COMMANDS_JSON}\"${ESCAPED_CMD}\""
      done
      COMMANDS_JSON="${COMMANDS_JSON}]"
    fi
    
    # Send command via SSM
    info "Sending SSH setup commands via SSM..."
    SSM_OUTPUT=$(aws ssm send-command \
      --instance-ids "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=${COMMANDS_JSON}" \
      --query 'Command.CommandId' \
      --output text 2>&1)
    
    COMMAND_ID=""
    if [ $? -eq 0 ] && [ -n "$SSM_OUTPUT" ] && [ "$SSM_OUTPUT" != "None" ]; then
      COMMAND_ID="$SSM_OUTPUT"
    else
      error "Could not send SSM command. Error: $SSM_OUTPUT"
    fi
    
    info "Command sent. Waiting for execution..."
    sleep 5
    
    # Wait for command to complete
    MAX_WAIT=60
    WAITED=0
    STATUS="Unknown"
    while [ $WAITED -lt $MAX_WAIT ]; do
      STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Status' \
        --output text 2>/dev/null || echo "Unknown")
      
      if [ "$STATUS" = "Success" ]; then
        log "SSH keys set up successfully!"
        break
      elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ] || [ "$STATUS" = "TimedOut" ]; then
        warn "Command failed with status: $STATUS"
        aws ssm get-command-invocation \
          --command-id "$COMMAND_ID" \
          --instance-id "$INSTANCE_ID" \
          --region "$AWS_REGION" \
          --query 'StandardErrorContent' \
          --output text 2>/dev/null || true
        error "SSH key setup failed"
      fi
      
      sleep 2
      WAITED=$((WAITED + 2))
    done
    
    if [ "$STATUS" != "Success" ]; then
      error "SSH key setup did not complete. Status: ${STATUS:-Unknown}"
    fi
  fi
else
  info "Skipping SSH key setup (--skip-ssh-keys)"
fi

#######################################
# Step 4: Configure SSH Config
#######################################

if [ "$SKIP_SSH_CONFIG" = false ]; then
  step "Configuring SSH Config for Remote-SSH"
  
  SSH_CONFIG_FILE="${HOME}/.ssh/config"
  SSH_CONFIG_DIR="$(dirname "$SSH_CONFIG_FILE")"
  
  # Create .ssh directory if it doesn't exist
  if [ ! -d "$SSH_CONFIG_DIR" ]; then
    mkdir -p "$SSH_CONFIG_DIR"
    chmod 700 "$SSH_CONFIG_DIR"
    log "Created ${SSH_CONFIG_DIR}"
  fi
  
  # Check if entry already exists
  if grep -q "^Host management-server" "$SSH_CONFIG_FILE" 2>/dev/null; then
    warn "SSH config entry for 'management-server' already exists"
    read -p "Do you want to update it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Remove existing entry
      sed -i.bak '/^Host management-server/,/^$/d' "$SSH_CONFIG_FILE" 2>/dev/null || true
      log "Removed existing entry"
    else
      info "Keeping existing SSH config entry"
      SKIP_SSH_CONFIG=true
    fi
  fi
  
  if [ "$SKIP_SSH_CONFIG" = false ]; then
    # Add new entry
    {
      echo ""
      echo "# Management Server for hello-aws project"
      echo "Host management-server"
      echo "    HostName localhost"
      echo "    Port 2222"
      echo "    User ec2-user"
      echo "    StrictHostKeyChecking no"
      echo "    UserKnownHostsFile /dev/null"
      echo "    ServerAliveInterval 60"
      echo "    ServerAliveCountMax 3"
      echo ""
    } >> "$SSH_CONFIG_FILE"
    chmod 600 "$SSH_CONFIG_FILE"
    log "Added SSH config entry for 'management-server'"
  fi
else
  info "Skipping SSH config setup (--skip-ssh-config)"
fi

#######################################
# Step 5: Start Port Forwarding (Optional)
#######################################

if [ "$START_PORT_FORWARD" = true ]; then
  step "Starting Port Forwarding in Background"
  
  CONNECT_SCRIPT="${PROJECT_ROOT}/03-infrastructure/scripts/connect-ssm.sh"
  if [ ! -f "$CONNECT_SCRIPT" ]; then
    warn "connect-ssm.sh not found. Skipping port forwarding."
    warn "You'll need to start it manually:"
    warn "  ${CONNECT_SCRIPT} --management --port-forward"
  else
    # Check if port forwarding is already running
    if lsof -ti:2222 > /dev/null 2>&1; then
      warn "Port 2222 is already in use. Port forwarding may already be running."
      info "If you need to restart it, kill the existing process first:"
      info "  lsof -ti:2222 | xargs kill"
    else
      info "Starting port forwarding in background..."
      nohup "$CONNECT_SCRIPT" --management --port-forward > /tmp/ssm-port-forward.log 2>&1 &
      PF_PID=$!
      sleep 3
      
      # Check if it's still running
      if kill -0 $PF_PID 2>/dev/null; then
        log "Port forwarding started (PID: $PF_PID)"
        info "Logs: /tmp/ssm-port-forward.log"
        info "To stop: kill $PF_PID"
      else
        warn "Port forwarding may have failed. Check logs: /tmp/ssm-port-forward.log"
      fi
    fi
  fi
else
  info "Port forwarding not started (use --start-port-forward to enable)"
fi

#######################################
# Step 6: Final Instructions
#######################################

step "Setup Complete!"

echo -e "${BOLD}Next Steps:${NC}\n"

if [ "$START_PORT_FORWARD" = false ]; then
  echo -e "1. ${CYAN}Start port forwarding${NC} (in a separate terminal):"
  echo -e "   ${BOLD}${PROJECT_ROOT}/03-infrastructure/scripts/connect-ssm.sh --management --port-forward${NC}"
  echo -e "   ${YELLOW}Keep this terminal running while using Remote-SSH${NC}\n"
fi

echo -e "2. ${CYAN}Connect via Remote-SSH in Cursor:${NC}"
echo -e "   - Press ${BOLD}Cmd+Shift+P${NC} (or ${BOLD}F1${NC})"
echo -e "   - Type ${BOLD}'Remote-SSH: Connect to Host'${NC}"
echo -e "   - Select ${BOLD}'management-server'${NC}"
echo -e "   - Cursor will open a new window connected to the remote server\n"

echo -e "3. ${CYAN}Open workspace on remote:${NC}"
echo -e "   - Once connected, go to ${BOLD}File > Open Folder${NC}"
echo -e "   - Navigate to ${BOLD}/home/ec2-user/hello-aws${NC}\n"

echo -e "4. ${CYAN}Transfer files (if needed):${NC}"
echo -e "   ${BOLD}scp -P 2222 -r <local-path> ec2-user@localhost:~/<target-path>${NC}\n"

echo -e "5. ${CYAN}Test SSH connection:${NC}"
echo -e "   ${BOLD}ssh management-server${NC}\n"

if [ "$START_PORT_FORWARD" = true ]; then
  echo -e "${YELLOW}Note:${NC} Port forwarding is running in the background."
  echo -e "To stop it, find the process: ${BOLD}lsof -ti:2222 | xargs kill${NC}\n"
fi

log "Remote-SSH setup complete! You can now connect to the management server."
