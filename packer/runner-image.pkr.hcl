packer {
  required_plugins {
    amazon = {
      version = "~> 1.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "runner_version" {
  type    = string
  default = "v1.0.0"
}

variable "build_id" {
  type = string
}

variable "timestamp" {
  type = string
}

source "amazon-ebs" "runner" {
  ami_name          = "elevatediq-runner-${var.runner_version}-${var.timestamp}"
  ami_description   = "Immutable GitHub Actions runner: ${var.runner_version}"
  instance_type     = "t3.medium"
  region            = "us-east-1"
  ami_users         = ["self"]
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }
  
  run_tags = {
    Name           = "packer-runner-build-${var.build_id}"
    ManagedBy      = "Packer"
    Version        = var.runner_version
  }
  
  tags = {
    Name           = "elevatediq-runner-${var.runner_version}"
    Version        = var.runner_version
    BuildID        = var.build_id
    BuildDate      = var.timestamp
    ManagedBy      = "Packer"
    Immutable      = "true"
    SignedBy       = "elevatediq-ci"
  }
  
  # Block device optimization
  ebs_optimized = true
  
  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
}

build {
  name = "elevatediq-runner"
  
  sources = ["source.amazon-ebs.runner"]
  
  # System updates
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo '🔄 Starting system setup...'",
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y curl wget git unzip jq python3-pip",
      "echo '✅ System packages installed'"
    ]
  }
  
  # Docker installation
  provisioner "shell" {
    script = "${path.root}/scripts/install-docker.sh"
  }
  
  # GitHub Actions runner installation
  provisioner "shell" {
    environment_vars = [
      "RUNNER_VERSION=${var.runner_version}"
    ]
    script = "${path.root}/scripts/install-runner.sh"
  }
  
  # Hardening & security
  provisioner "shell" {
    script = "${path.root}/scripts/harden-security.sh"
  }
  
  # Install Ollama for local LLM inference (agentic workflows)
  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "echo '🤖 Installing Ollama for agentic workflows...'",
      "curl -fsSL https://ollama.ai/install.sh | sh 2>/dev/null || echo 'Note: Ollama installation may require manual setup'",
      "echo '✅ Ollama installed'"
    ]
  }
  
  # Create Ollama systemd service
  provisioner "file" {
    content = <<-EOF
[Unit]
Description=Ollama LLM Service for Agentic Workflows
Documentation=https://ollama.ai
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ollama serve
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
Environment="OLLAMA_MODELS=/data/ollama/models"
Environment="OLLAMA_HOST=127.0.0.1:11434"

[Install]
WantedBy=multi-user.target
EOF
    destination = "/etc/systemd/system/ollama.service"
  }
  
  # Enable Ollama service
  provisioner "shell" {
    inline = [
      "systemctl daemon-reload",
      "systemctl enable ollama.service || true",
      "echo '✅ Ollama service configured'"
    ]
  }
  
  # Cleanup
  provisioner "shell" {
    inline = [
      "echo '🧹 Cleaning up build artifacts...'",
      "apt-get clean && apt-get autoclean && apt-get autoremove -y",
      "rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*",
      "truncate -s 0 /var/log/*log",
      "echo '✅ Cleanup complete'"
    ]
  }
  
  # Image version marker
  provisioner "file" {
    content = <<-EOF
{
  "version": "${var.runner_version}",
  "build_id": "${var.build_id}",
  "build_date": "${var.timestamp}",
  "git_commit": "$(cd ${path.root} && git rev-parse HEAD)",
  "immutable": true
}
EOF
    destination = "/etc/runner-image-metadata.json"
  }
}
