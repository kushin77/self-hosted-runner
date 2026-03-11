variable "backend_url" {
  description = "Backend host URL used for uptime checks (host portion, e.g. my-backend.example.com). Empty disables backend uptime check."
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "Frontend host URL used for uptime checks (host portion, e.g. my-frontend.example.com). Empty disables frontend uptime check."
  type        = string
  default     = ""
}
