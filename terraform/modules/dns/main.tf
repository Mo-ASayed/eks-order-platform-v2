resource "aws_route53_zone" "this" {
  name          = var.domain_name
  comment       = "Managed by Terraform"
  force_destroy = false

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
