terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

locals {
  webhook_secret_arn_effective = var.webhook_secret_arn != "" ? var.webhook_secret_arn : (var.create_webhook_secret ? (aws_secretsmanager_secret.webhook[0].arn) : "")
}

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
  name                = "runner-asg"
  max_size            = var.max_capacity
  min_size            = 0
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
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
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.lc_topic.arn
      }
    ]
  })
}

resource "aws_autoscaling_lifecycle_hook" "spot_termination" {
  name                    = "spot-termination-hook"
  autoscaling_group_name  = aws_autoscaling_group.runner_asg.name
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = aws_sns_topic.lc_topic.arn
  role_arn                = aws_iam_role.asg_notification_role.arn
  heartbeat_timeout       = 300
  default_result          = "CONTINUE"
}

# SQS queue to surface lifecycle notifications to a consumer (Lambda or worker)
resource "aws_sqs_queue" "lifecycle_queue" {
  name                       = "runner-lifecycle-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
}

# Subscribe SQS queue to SNS topic
resource "aws_sns_topic_subscription" "sqs_sub" {
  topic_arn = aws_sns_topic.lc_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.lifecycle_queue.arn

  # Allow SNS to send messages to SQS
  depends_on = [aws_sqs_queue.lifecycle_queue]
}

# Allow SNS principal to send messages to the SQS queue
resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.lifecycle_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage",
        Effect    = "Allow",
        Principal = { Service = "sns.amazonaws.com" },
        Action    = "sqs:SendMessage",
        Resource  = aws_sqs_queue.lifecycle_queue.arn,
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.lc_topic.arn }
        }
      }
    ]
  })
}

# Optional: create the Secrets Manager secret for the webhook (WARNING: secret stored in state)
resource "aws_secretsmanager_secret" "webhook" {
  count = var.create_webhook_secret ? 1 : 0
  name  = var.webhook_secret_name
}

resource "aws_secretsmanager_secret_version" "webhook_value" {
  count       = var.create_webhook_secret ? 1 : 0
  secret_id   = aws_secretsmanager_secret.webhook[0].id
  secret_string = var.webhook_secret_value
}

# Optional: Lambda consumer that reads lifecycle messages from SQS and triggers a drain webhook
data "archive_file" "lifecycle_handler_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../services/spot-lifecycle/handler.py"
  output_path = "${path.module}/lifecycle_handler.zip"
}

resource "aws_iam_role" "lambda_role" {
  count = var.enable_lifecycle_handler ? 1 : 0
  name  = "runner-lifecycle-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "lambda.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_logs_policy" {
  count = var.enable_lifecycle_handler ? 1 : 0
  name  = "lambda-logs-policy"
  role  = aws_iam_role.lambda_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# If provided, grant the Lambda permission to read the Secrets Manager secret
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  count = var.enable_lifecycle_handler && (length(var.webhook_secret_arn) > 0 || var.create_webhook_secret) ? 1 : 0
  name  = "lambda-secrets-policy"
  role  = aws_iam_role.lambda_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = local.webhook_secret_arn_effective
      }
    ]
  })
}

resource "aws_lambda_function" "lifecycle_handler" {
  count            = var.enable_lifecycle_handler ? 1 : 0
  filename         = data.archive_file.lifecycle_handler_zip.output_path
  function_name    = "runner-lifecycle-handler"
  role             = aws_iam_role.lambda_role[0].arn
  handler          = "handler.lambda_handler"
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  source_code_hash = data.archive_file.lifecycle_handler_zip.output_base64sha256

  environment {
    variables = merge(var.lambda_env, local.webhook_secret_arn_effective == "" ? {} : {"RUNNER_DRAIN_SECRET_ARN" = local.webhook_secret_arn_effective})
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  count            = var.enable_lifecycle_handler ? 1 : 0
  event_source_arn = aws_sqs_queue.lifecycle_queue.arn
  function_name    = aws_lambda_function.lifecycle_handler[0].arn
  batch_size       = 1
  enabled          = true
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count             = var.enable_lifecycle_handler ? 1 : 0
  name              = "/aws/lambda/runner-lifecycle-handler"
  retention_in_days = 14
}
