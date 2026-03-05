variable "vpc_id" {
  description = "VPC ID to deploy instances into"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
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
