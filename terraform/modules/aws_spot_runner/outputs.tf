output "asg_id" {
  description = "Autoscaling group id"
  value       = aws_autoscaling_group.runner_asg.id
}

output "launch_template_id" {
  description = "Launch template id"
  value       = aws_launch_template.runner_lt.id
}
