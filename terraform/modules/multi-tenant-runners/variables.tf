variable "tenant_id" {
  description = "Identifier for the specific tenant or engineering group"
  type        = string
}

variable "runner_group_name" {
  description = "Name for the GitHub Runner group (must exist or be created by ID)"
  type        = string
}

variable "vpc_id" {
  description = "Target VPC for isolated runner deployment"
  type        = string
}

variable "subnet_ids" {
  description = "Target subnets within the isolated VPC"
  type        = list(string)
}

variable "labels" {
  description = "Additional labels for runner isolation (e.g. tier:high-sec, group:payments)"
  type        = map(string)
  default     = {}
}
