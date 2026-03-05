terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {}

resource "aws_launch_template" "runner_lt" {
  name_prefix   = "runner-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  key_name = var.key_name

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_autoscaling_group" "runner_asg" {
  name                      = "runner-asg"
  max_size                  = var.max_capacity
  min_size                  = 0
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.subnet_ids
  launch_template {
    id      = aws_launch_template.runner_lt.id
    version = "$Latest"
  }

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.runner_lt.id
        version            = "$Latest"
      }
    }

    instances_distribution {
      on_demand_percentage_above_base_capacity = 20
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  tag {
    key                 = "Name"
    value               = "runner-asg"
    propagate_at_launch = true
  }
}

# Lifecycle handling: notify via SNS on instance termination (spot interruptions)
resource "aws_sns_topic" "lc_topic" {
  name = "runner-asg-lifecycle-topic"
}

resource "aws_iam_role" "asg_notification_role" {
  name = "asg-notification-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "autoscaling.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "asg_notification_policy" {
  name = "asg-notify-publish"
  role = aws_iam_role.asg_notification_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.lc_topic.arn
      }
    ]
  })
}

resource "aws_autoscaling_lifecycle_hook" "spot_termination" {
  name                   = "spot-termination-hook"
  autoscaling_group_name = aws_autoscaling_group.runner_asg.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = aws_sns_topic.lc_topic.arn
  role_arn               = aws_iam_role.asg_notification_role.arn
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"
}
