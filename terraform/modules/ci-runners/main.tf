# GitHub Actions Self-Hosted Runner Terraform Module
# Provisions complete runner infrastructure with health monitoring

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35"
    }
  }
}

variable "project_name" {
  type        = string
  description = "Project name for runner infrastructure"
  default     = "elevatediq-runners"
}

variable "environment" {
  type        = string
  description = "Environment (dev, staging, prod)"
  default     = "prod"
}

variable "runner_count" {
  type        = number
  description = "Number of runner instances to create"
  default     = 2
}

variable "instance_type_standard" {
  type        = string
  description = "Instance type for standard runners"
  default     = "t3.medium" # 2 vCPU, 4GB RAM
}

variable "instance_type_highmem" {
  type        = string
  description = "Instance type for high-memory runners"
  default     = "r5.xlarge" # 4 vCPU, 32GB RAM
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for runner deployment"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for runner deployment"
}

variable "runner_token" {
  type        = string
  sensitive   = true
  description = "GitHub runner registration token"
}

variable "github_owner" {
  type        = string
  description = "GitHub repository owner (org or user)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

# Data source: Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Security Group for runners
resource "aws_security_group" "runners" {
  name_prefix = "${var.project_name}-"
  description = "Security group for GitHub Actions self-hosted runners"
  vpc_id      = var.vpc_id

  # Allow outbound HTTPS (for GitHub API)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound NTP
  egress {
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
  }
}

# IAM role for runner instances
resource "aws_iam_role" "runner" {
  name_prefix = "${var.project_name}-runner-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-runner-role"
    Environment = var.environment
  }
}

# IAM policy for spot instance handling (CloudWatch, Systems Manager)
resource "aws_iam_role_policy" "runner_spot" {
  name_prefix = "${var.project_name}-runner-spot-"
  role        = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name_prefix = "${var.project_name}-runner-"
  role        = aws_iam_role.runner.name
}

# User data for runner setup
locals {
  runner_setup_script = base64encode(templatefile("${path.module}/runner_setup.sh", {
    runner_token   = var.runner_token
    github_owner   = var.github_owner
    github_repo    = var.github_repo
    runner_dir     = "/home/ubuntu/actions-runner"
    RUNNER_VERSION = "" # Fetched dynamically
    RUNNER_ARCH    = "" # Fetched dynamically
    RUNNER_USER    = "ubuntu"
  }))
}

# Standard runner instances
resource "aws_instance" "runners_standard" {
  count                       = ceil(var.runner_count / 2)
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_standard
  vpc_security_group_ids      = [aws_security_group.runners.id]
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  iam_instance_profile        = aws_iam_instance_profile.runner.name
  user_data                   = local.runner_setup_script
  associate_public_ip_address = false
  monitoring                  = true

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-standard-${count.index}"
    Environment = var.environment
    RunnerTier  = "standard"
  }

  depends_on = [
    aws_iam_instance_profile.runner
  ]
}

# High-memory runner instances
resource "aws_instance" "runners_highmem" {
  count                       = var.runner_count - ceil(var.runner_count / 2)
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_highmem
  vpc_security_group_ids      = [aws_security_group.runners.id]
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  iam_instance_profile        = aws_iam_instance_profile.runner.name
  user_data                   = local.runner_setup_script
  associate_public_ip_address = false
  monitoring                  = true

  root_block_device {
    volume_size           = 200
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-highmem-${count.index}"
    Environment = var.environment
    RunnerTier  = "high-mem"
  }

  depends_on = [
    aws_iam_instance_profile.runner
  ]
}

# Outputs
output "standard_runner_ids" {
  description = "IDs of standard runner instances"
  value       = aws_instance.runners_standard[*].id
}

output "highmem_runner_ids" {
  description = "IDs of high-memory runner instances"
  value       = aws_instance.runners_highmem[*].id
}

output "standard_runner_private_ips" {
  description = "Private IPs of standard runners"
  value       = aws_instance.runners_standard[*].private_ip
}

output "highmem_runner_private_ips" {
  description = "Private IPs of high-memory runners"
  value       = aws_instance.runners_highmem[*].private_ip
}

output "security_group_id" {
  description = "Security group ID for runners"
  value       = aws_security_group.runners.id
}
