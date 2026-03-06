output "record_fqdn" {
  value = aws_route53_record.gitlab.fqdn
}

output "record_id" {
  value = aws_route53_record.gitlab.id
}
