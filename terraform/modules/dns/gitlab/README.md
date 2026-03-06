Terraform module: gitlab DNS record

This module creates an authoritative DNS A record for `gitlab.internal.elevatediq.com` in Route53.

Usage (example):

module "gitlab_dns" {
  source   = "./modules/dns/gitlab"
  zone_id  = var.route53_zone_id
  dns_name = "gitlab.internal.elevatediq.com"
  dns_value = "192.168.168.42"
  dns_ttl  = 300
}

Notes:
- This is a conservative skeleton to be reviewed and adapted to your Terraform organization and state backend.
- Ensure AWS provider credentials and `zone_id` are supplied via your normal Terraform provider configuration or workspace variables.
