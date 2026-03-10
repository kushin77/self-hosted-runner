variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "image" {
  type = string
}

variable "repository" {
  type = string
}

variable "image_name" {
  type = string
}

variable "tag" {
  type = string
  default = "latest"
}

variable "schedule" {
  type = string
  default = "0 3 * * *" # daily 03:00 UTC
}

variable "scheduler_sa" {
  type = string
}
