#!/bin/bash
# Management Server User Data
# Configures the management server for administrative tasks

set -e

# Update system
yum update -y

# Install common tools
# Note: kubectl is not available in Amazon Linux 2023 repos, installed via curl below
# Note: curl-minimal is pre-installed on Amazon Linux 2023, no need to install curl
yum install -y \
  git \
  wget \
  jq \
  unzip \
  vim \
  htop \
  net-tools \
  bind-utils \
  telnet \
  nc \
  awscli \
  docker \
  openssh-server

# Install AWS CLI v2 (if not already installed)
if ! command -v aws &> /dev/null || aws --version | grep -q "aws-cli/1"; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf aws awscliv2.zip
fi

# Install kubectl (if not already installed)
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
fi

# Install eksctl (optional, for EKS management)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin

# Install GitHub CLI (gh)
if ! command -v gh &> /dev/null; then
  GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | grep tag_name | cut -d '"' -f 4 || echo "v2.47.0")
  curl -LO "https://github.com/cli/cli/releases/download/${GH_VERSION}/gh_${GH_VERSION#v}_linux_amd64.tar.gz"
  tar -xzf gh_${GH_VERSION#v}_linux_amd64.tar.gz
  mv gh_${GH_VERSION#v}_linux_amd64/bin/gh /usr/local/bin/
  chmod +x /usr/local/bin/gh
  rm -rf gh_${GH_VERSION#v}_linux_amd64 gh_${GH_VERSION#v}_linux_amd64.tar.gz
fi

# Install Helm
if ! command -v helm &> /dev/null; then
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Install Helmfile
if ! command -v helmfile &> /dev/null; then
  HELMFILE_VERSION=$(curl -s https://api.github.com/repos/helmfile/helmfile/releases/latest 2>/dev/null | grep tag_name | cut -d '"' -f 4 || echo "v0.168.0")
  curl -LO "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz"
  tar -xzf helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz
  mv helmfile /usr/local/bin/
  chmod +x /usr/local/bin/helmfile
  rm -f helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
  TERRAFORM_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest 2>/dev/null | grep tag_name | cut -d '"' -f 4 || echo "1.9.0")
  curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION#v}/terraform_${TERRAFORM_VERSION#v}_linux_amd64.zip"
  unzip -q terraform_${TERRAFORM_VERSION#v}_linux_amd64.zip
  mv terraform /usr/local/bin/
  chmod +x /usr/local/bin/terraform
  rm -f terraform_${TERRAFORM_VERSION#v}_linux_amd64.zip
fi

# Configure hostname
hostnamectl set-hostname ${hostname}

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Session Manager plugin (for SSM access)
if [ ! -f /usr/local/bin/session-manager-plugin ]; then
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "/tmp/session-manager-plugin.rpm"
  yum install -y /tmp/session-manager-plugin.rpm
  rm /tmp/session-manager-plugin.rpm
fi

# Configure SSM Agent (should be pre-installed on Amazon Linux)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Configure SSH server (for Remote-SSH access via port forwarding)
systemctl enable sshd
systemctl start sshd

# Ensure SSH service is running
if ! systemctl is-active --quiet sshd; then
  systemctl start sshd
fi

# Create management directory
mkdir -p /home/ec2-user/management
chown ec2-user:ec2-user /home/ec2-user/management

# Log completion
echo "Management server setup completed at $(date)" >> /var/log/user-data.log

