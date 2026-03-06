resource "aws_route53_record" "gitlab" {
  zone_id = var.zone_id
  name    = var.dns_name
  type    = "A"
  ttl     = var.dns_ttl
  records = [var.dns_value]
}
