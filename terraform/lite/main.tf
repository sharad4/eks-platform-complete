provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.name, Edition = "lite", ManagedBy = "terraform" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  arm      = startswith(var.instance_type, "t4g.") || startswith(var.instance_type, "m7g.") || startswith(var.instance_type, "c7g.")
  ami_path = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.arm ? "arm64" : "x86_64"}"
  repo_url = "https://github.com/${var.github_org}/${var.github_repo}.git"
}

# Amazon Linux 2023: SSM agent preinstalled, so no SSH key or open port 22 needed.
data "aws_ssm_parameter" "ami" {
  name = local.ami_path
}

# --- Network: one public subnet, no NAT gateway (a NAT costs ~$32/month) ------
resource "aws_vpc" "this" {
  cidr_block           = "10.50.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.50.0.0/26"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Only web ports in. No SSH, no Kubernetes API: administer through SSM.
resource "aws_security_group" "node" {
  name_prefix = "${var.name}-"
  description = "k3s single node: HTTP/HTTPS in, anything out"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP (Traefik)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_cidrs
  }
  ingress {
    description = "HTTPS (Traefik)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.http_cidrs
  }
  egress {
    description = "Package, image and GitHub downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Access: SSM Session Manager ----------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.node.name
}

# --- The node -----------------------------------------------------------------
resource "aws_instance" "node" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # pods may reach IMDS; set 1 to block that
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    repo_url       = local.repo_url
    branch         = var.repo_branch
    k3s_version    = var.k3s_version
    argocd_version = var.argocd_version
    argocd_mode    = var.argocd_mode
    swap_gb        = var.swap_gb
  })

  tags = { Name = var.name }

  lifecycle {
    # user_data only runs on first boot; do not replace the VM (and its data)
    # because the template changed. Taint the instance deliberately instead.
    ignore_changes = [user_data, ami]
  }
}

# A stable address across stop/start. NOTE: AWS charges for public IPv4
# addresses (~$0.005/h); on the free plan this is covered by credits/free hours.
resource "aws_eip" "node" {
  domain   = "vpc"
  instance = aws_instance.node.id
  tags     = { Name = var.name }
}

# --- Cost guard ----------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count        = var.budget_email == "" ? 0 : 1
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
