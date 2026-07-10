# ---------------------------------------------------------------------------
# Outputs consumed by EKS, Karpenter and the stateful tier.
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = aws_subnet.private_subnet[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public_subnet[*].id
}

output "nat_gateway_ids" {
  description = "NAT gateway ID"
  value       = aws_nat_gateway.this[*].id
}

output "availability_zones" {
  description = "The AZs used. "
  value       = var.availability_zones
}
