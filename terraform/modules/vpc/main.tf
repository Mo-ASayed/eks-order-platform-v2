# ===========================================================================
# VPC shape: 3 public and 3 private subnets across 3 AZs. Public subnets host
# internet-facing LBs and NAT; private subnets host nodes, pods and data stores.
# ===========================================================================

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block

  # EKS, the VPC CNI and service discovery all expect VPC DNS to be enabled.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

# Lock down the VPC default security group: no ingress/egress rules. Nothing
# should use it — workloads get purpose-built SGs (CKV2_AWS_12).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}


resource "aws_subnet" "public_subnet" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # anything here gets a public IP

  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"

    # AWS Load Balancer Controller uses this for internet-facing LBs.
    "kubernetes.io/role/elb" = "1"
    # Marks this subnet as shared with the cluster.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}


resource "aws_subnet" "private_subnet" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"

    # AWS Load Balancer Controller uses this for internal LBs.
    "kubernetes.io/role/internal-elb"           = "1"
    "karpenter.sh/discovery"                    = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# NAT lets private subnets reach the internet without accepting inbound traffic.
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones) # One NAT is cheaper; per-AZ NAT improves resilience.
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id # NAT lives in public subnets.

  tags = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this] # NAT needs the IGW first.
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public_rt_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_route_table" "private_rt" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    # Single NAT uses index 0; otherwise each AZ routes to its own NAT.
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
  }

  tags = merge(var.tags, { Name = "${var.name}-private-rt-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private_rt_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}
