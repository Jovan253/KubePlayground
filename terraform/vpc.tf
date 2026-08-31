# Step 3 — Network.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs is EKS's minimum. Taking more would mean more subnets to no benefit
  # at this size.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # /16 for the VPC
  vpc_cidr = "10.0.0.0/16"
}

# VNet basically
resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  # Both required by EKS. Without them, in-cluster DNS resolution of AWS
  # endpoints breaks in ways that are painful to diagnose.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  for_each = { for i, az in local.azs : az => i }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(local.vpc_cidr, 4, each.value)

  # Nodes need public IPs since there is no NAT to route through.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${each.key}"

    # EKS discovers subnets by TAG, not by configuration.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

# A subnet is only "public" because its route table has a route to an internet
# gateway. Nothing about the subnet itself says so — this association is what
# makes the name true.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
