variable "zone_id" {
  description = "Route53 zone id for internal.elevatediq.com"
  type        = string
}

variable "dns_name" {
  description = "FQDN to create"
  type        = string
  default     = "gitlab.internal.elevatediq.com"
}

variable "dns_value" {
  description = "IP address for the A record"
  type        = string
  default     = "192.168.168.42"
}

variable "dns_ttl" {
  description = "TTL for DNS record"
  type        = number
  default     = 300
}
