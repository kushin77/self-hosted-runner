variable "vpc_id" {
  description = "VPC ID to deploy instances into"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type (use t2.small or smaller for free-tier eligibility)"
  type        = string
  default     = "t2.small"
}

variable "desired_capacity" {
  description = "Desired capacity of ASG"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum capacity of ASG"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = ""
}

variable "enable_lifecycle_handler" {
  description = "Whether to deploy a Lambda-based lifecycle handler that consumes the SQS lifecycle queue"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Lambda runtime for the lifecycle handler"
  type        = string
  default     = "python3.11"
}

variable "lambda_memory_size" {
  description = "Memory size (MB) for the lifecycle handler Lambda"
  type        = number
  default     = 128
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for the lifecycle handler Lambda"
  type        = number
  default     = 60
}

variable "lambda_env" {
  description = "Map of environment variables to set on the Lambda function"
  type        = map(string)
  default     = {}
}

variable "webhook_secret_arn" {
  description = "Optional Secrets Manager secret ARN that contains the runner drain webhook URL. If provided, the Lambda will be granted permission to read it and will fetch at runtime."
  type        = string
  default     = ""
}

variable "create_webhook_secret" {
  description = "If true, Terraform will create a Secrets Manager secret using `webhook_secret_value`. Use with caution; secret will be stored in state."
  type        = bool
  default     = false
}

variable "webhook_secret_value" {
  description = "(Optional) Secret string to populate when creating the webhook secret. Only used if `create_webhook_secret` is true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "webhook_secret_name" {
  description = "Name for the created Secrets Manager secret when `create_webhook_secret` is true"
  type        = string
  default     = "runner/drain-webhook"
}
