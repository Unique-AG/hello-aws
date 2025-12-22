#!/usr/bin/env bash
#######################################
# Setup SSH Keys on Management Server
#######################################
# Sets up SSH keys on the management server via SSM
# so you can use SSH/SCP and Remote SSH in Cursor
#
# Usage:
#   ./scripts/setup-ssh-keys.sh
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

AWS_REGION="eu-central-2"

# Get instance ID
INSTANCE_ID=$(cd "${PROJECT_ROOT}/03-infrastructure/terraform" && terraform output -raw management_server_instance_id 2>/dev/null || echo "")
if [ -z "$INSTANCE_ID" ]; then
  warn "Could not get instance ID from Terraform"
  exit 1
fi

info "Setting up SSH keys on instance: ${INSTANCE_ID}"

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
  # Auto-add existing key (non-interactive)
  PUB_KEY=$(cat ~/.ssh/id_${LOCAL_SSH_KEY}.pub)
  info "Will add your existing public key"
else
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
SSH_SETUP_COMMANDS+=("echo 'Public key:'")
SSH_SETUP_COMMANDS+=("cat /home/ec2-user/.ssh/id_ed25519.pub 2>/dev/null || cat /home/ec2-user/.ssh/authorized_keys | tail -1")

# Join commands
COMMAND_STRING=$(IFS=$'\n'; echo "${SSH_SETUP_COMMANDS[*]}")

# Send command via SSM
info "Sending SSH setup commands..."

# Check if jq is available
if ! command -v jq &> /dev/null; then
  warn "jq not found. Building JSON manually..."
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
else
  # Use jq to build JSON array
  COMMANDS_JSON=$(printf '%s\n' "${SSH_SETUP_COMMANDS[@]}" | jq -R . | jq -s .)
fi

# Send command via SSM with better error handling
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
  warn "Could not send SSM command"
  warn "Error output: $SSM_OUTPUT"
  exit 1
fi

info "Command sent. Waiting for execution..."
sleep 5

# Wait for command to complete
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Unknown")
  
  if [ "$STATUS" = "Success" ]; then
    log "SSH keys set up successfully!"
    info "Output:"
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query 'StandardOutputContent' \
      --output text
    break
  elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Cancelled" ] || [ "$STATUS" = "TimedOut" ]; then
    warn "Command failed with status: $STATUS"
    aws ssm get-command-invocation \
      --command-id "$COMMAND_ID" \
      --instance-id "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query 'StandardErrorContent' \
      --output text
    exit 1
  fi
  
  sleep 2
  WAITED=$((WAITED + 2))
done

if [ "$STATUS" != "Success" ]; then
  warn "Command did not complete. Status: ${STATUS:-Unknown}"
  exit 1
fi

log "SSH keys are now set up!"
info "Next steps:"
echo "  1. Start port forwarding: ./03-infrastructure/scripts/connect-ssm.sh --management --port-forward"
echo "  2. Test SSH: ssh -p 2222 ec2-user@localhost"
echo "  3. Transfer files: scp -P 2222 -r <local-path> ec2-user@localhost:~/"
echo "  4. Configure Remote SSH in Cursor (see REMOTE-SSH-SETUP.md)"
