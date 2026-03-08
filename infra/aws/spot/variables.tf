variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID to use for runners"
  type        = string
}

variable "spot_max_price" {
  description = "Max price for spot instances (empty for on-demand fallback)"
  type        = string
  default     = ""
}
