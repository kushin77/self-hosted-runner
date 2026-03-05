output "asg_id" {
  description = "Autoscaling group id"
  value       = aws_autoscaling_group.runner_asg.id
}

output "launch_template_id" {
  description = "Launch template id"
  value       = aws_launch_template.runner_lt.id
}

output "lifecycle_sns_topic_arn" {
  description = "SNS topic ARN used for ASG lifecycle notifications"
  value       = aws_sns_topic.lc_topic.arn
}

output "lifecycle_hook_name" {
  description = "Name of the lifecycle hook"
  value       = aws_autoscaling_lifecycle_hook.spot_termination.name
}

output "lifecycle_sqs_queue_url" {
  description = "SQS queue URL for lifecycle notifications"
  value       = aws_sqs_queue.lifecycle_queue.id
}

output "lifecycle_sqs_queue_arn" {
  description = "SQS queue ARN for lifecycle notifications"
  value       = aws_sqs_queue.lifecycle_queue.arn
}

output "lifecycle_handler_lambda_arn" {
  description = "ARN of the lifecycle handler Lambda function (if enabled)"
  value       = try(aws_lambda_function.lifecycle_handler[0].arn, "")
}

output "lifecycle_handler_lambda_name" {
  description = "Name of the lifecycle handler Lambda function (if enabled)"
  value       = try(aws_lambda_function.lifecycle_handler[0].function_name, "")
}

output "lifecycle_handler_role_arn" {
  description = "IAM role ARN used by the lifecycle handler Lambda"
  value       = try(aws_iam_role.lambda_role[0].arn, "")
}

output "lifecycle_webhook_secret_arn_set" {
  description = "Whether a webhook secret ARN was configured for the lifecycle handler"
  value       = var.webhook_secret_arn
}

output "lifecycle_webhook_secret_arn_effective" {
  description = "Effective webhook secret ARN used by the Lambda (either provided or created)"
  value       = try(local.webhook_secret_arn_effective, "")
}
