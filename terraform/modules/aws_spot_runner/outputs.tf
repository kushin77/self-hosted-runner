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
