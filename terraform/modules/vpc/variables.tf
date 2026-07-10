
variable "name" {
  description = "Name prefix for all resources, e.g. 'eks-v2-dev'. Shows up in tags and the AWS console."
  type        = string
}

variable "cluster_name" {
  description = "The name of the cluster the subnets belong to. Kept separate from 'name' because the cluster name must match exactly what the EKS module uses, or load balancers and Karpenter won't find their subnets."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. /16 gives about 65k IPs; the VPC CNI assigns pods real VPC IPs, so keep this large."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread across."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "The brief requires exactly 3 AZs."
  }
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ for private subnets. Nodes, pods and databases live here, so keep these large."
  type        = list(string)
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"] # ~8k IPs each
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for public subnets (NAT gateways and the internet-facing NLB live here)"
  type        = list(string)
  default     = ["10.0.96.0/22", "10.0.100.0/22", "10.0.104.0/22"] # ~1k IPs each
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for dev cost control. Set false for one NAT per AZ."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags for this module. Provider default_tags still apply to all infrastructure."
  type        = map(string)
  default = {
  }
}
