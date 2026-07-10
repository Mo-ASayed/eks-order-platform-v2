output "zone_id" {
  description = "Route53 hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Authoritative name servers for the hosted zone."
  value       = aws_route53_zone.this.name_servers
}
