# =============================================================================
# VPC module: three-tier network
#
#   public   (/24 per AZ)  -> ALBs, NAT gateways. Has a route to the IGW.
#   private  (/19 per AZ)  -> EKS nodes AND pods. Egress via NAT only.
#   data     (/24 per AZ)  -> RDS, ElastiCache. NO internet route at all.
#
# Why is private so much bigger?  The AWS VPC CNI gives every pod a real VPC IP.
# Small private subnets are the #1 cause of "pods stuck Pending: no IPs".
#
# Layout for a 10.10.0.0/16 VPC (3 AZs):
#   public   10.10.0.0/24, 10.10.1.0/24, 10.10.2.0/24
#   data     10.10.10.0/24, 10.10.11.0/24, 10.10.12.0/24
#   private  10.10.32.0/19, 10.10.64.0/19, 10.10.96.0/19
# =============================================================================

locals {
  az_count  = length(var.azs)
  nat_count = var.single_nat_gateway ? 1 : local.az_count

  public_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.cidr, 8, i)]
  data_cidrs    = [for i in range(local.az_count) : cidrsubnet(var.cidr, 8, i + 10)]
  private_cidrs = [for i in range(local.az_count) : cidrsubnet(var.cidr, 3, i + 1)]

  tags = merge(var.tags, { Module = "vpc" })
}

data "aws_region" "current" {}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true # required by EKS and VPC endpoints
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.name })
}

# Lock down the default SG: nothing should accidentally use it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-default-DO-NOT-USE" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = var.name })
}

# -----------------------------------------------------------------------------
# Public tier
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false # nothing should get a public IP implicitly

  tags = merge(local.tags, {
    Name                     = "${var.name}-public-${var.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # tells the ALB controller: internet-facing LBs go here
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# NAT gateways (one shared, or one per AZ)
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count      = local.nat_count
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, { Name = "${var.name}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.this]

  tags = merge(local.tags, { Name = "${var.name}-${var.azs[count.index]}" })
}

# -----------------------------------------------------------------------------
# Private tier (EKS nodes + pods)
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.tags, {
    Name                              = "${var.name}-private-${var.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"               # internal LBs go here
    "karpenter.sh/discovery"          = var.cluster_name # Karpenter finds subnets by this tag
  })
}

# One route table per AZ so each AZ egresses through ITS OWN NAT when
# single_nat_gateway = false (avoids cross-AZ data charges and AZ coupling).
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-private-${var.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count = local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# Data tier (RDS / ElastiCache): intentionally has NO default route.
# Even a misconfigured SG cannot let a database talk to the internet.
# -----------------------------------------------------------------------------
resource "aws_subnet" "data" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.tags, {
    Name = "${var.name}-data-${var.azs[count.index]}"
    Tier = "data"
  })
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-data" })
}

resource "aws_route_table_association" "data" {
  count          = local.az_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# -----------------------------------------------------------------------------
# S3 gateway endpoint: free, and keeps S3 traffic (image layers from ECR are
# stored in S3!) off the NAT gateway, which is billed per GB.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(aws_route_table.private[*].id, [aws_route_table.data.id])

  tags = merge(local.tags, { Name = "${var.name}-s3" })
}

# -----------------------------------------------------------------------------
# VPC flow logs -> CloudWatch (security forensics + "why can't A reach B?")
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "flow_write" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow_write.json
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow.arn

  tags = merge(local.tags, { Name = var.name })
}
