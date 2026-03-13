variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "milestone-organizer-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.26"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "node_groups" {
  type = map(any)
  default = {
    default = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1
      instance_type    = "t3.medium"
    }
  }
}

variable "tags" {
  type = map(string)
  default = {}
}
