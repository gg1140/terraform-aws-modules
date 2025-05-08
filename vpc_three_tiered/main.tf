# Variables

variable "prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnets_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks of the public subnets"
  default     = []
  validation {
    condition     = length(var.public_subnets_cidrs) == length(var.availability_zones)
    error_message = "public_subnets_cidrs must have the same number of elements as availability_zones."
  }
}

variable "private_subnets_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks of the private subnets"
  default     = []
  validation {
    condition     = length(var.private_subnets_cidrs) == length(var.availability_zones)
    error_message = "private_subnets_cidrs must have the same number of elements as availability_zones."
  }
}

variable "database_subnets_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks of the database subnets"
  default     = []
  validation {
    condition     = length(var.database_subnets_cidrs) == length(var.availability_zones)
    error_message = "database_subnets_cidrs must have the same number of elements as availability_zones."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZs to create resources in"
  default     = []
}

variable "create_nat_gateway" {
  type        = bool
  description = "NAT Gateway will be created for each public subnet when true"
}

variable "use_existing_eips" {
  type        = bool
  description = "Use existing EIPs for NAT Gateways"
}

variable "existing_eip_ids" {
  type        = list(string)
  default     = []
  description = "EIP IDs of the NAT Gateways"
}

variable "interface_vpc_endpoints" {
  type        = list(string)
  description = "List of interface type VPC endpoints to create. The strings are the last part of an endpoint. e.g., com.amazonaws.<region>.<endpoint>"
}

# Outputs

output "vpc_id" {
  value = aws_vpc.main_vpc.id
}

output "public_subnet_ids" {
  value = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  value = [for subnet in aws_subnet.private : subnet.id]
}

output "database_subnet_ids" {
  value = [for subnet in aws_subnet.database : subnet.id]
}

output "database_subnet_group_name" {
  value = aws_db_subnet_group.database.name
}

# Resources

resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each          = toset(var.availability_zones)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = element(var.public_subnets_cidrs, index(var.availability_zones, each.key))
  availability_zone = each.key
  tags              = { Name = "${var.prefix}-public-subnet-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each          = toset(var.availability_zones)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = element(var.private_subnets_cidrs, index(var.availability_zones, each.key))
  availability_zone = each.key
  tags              = { Name = "${var.prefix}-private-subnet-${each.key}" }
}

resource "aws_subnet" "database" {
  for_each          = toset(var.availability_zones)
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = element(var.database_subnets_cidrs, index(var.availability_zones, each.key))
  availability_zone = each.key
  tags              = { Name = "${var.prefix}-database-subnet-${each.key}" }
}

resource "aws_db_subnet_group" "database" {
  name       = "${var.prefix}-database-subnet-group"
  subnet_ids = [for subnet in aws_subnet.database : subnet.id]
  tags       = { Name = "${var.prefix}-database-subnet-group" }
}

# Route Tables and Associations
# Public
resource "aws_route_table" "public" {
  for_each = aws_subnet.public
  vpc_id   = aws_vpc.main_vpc.id
  tags     = { Name = "${var.prefix}-public-route-table-${each.value.availability_zone}" }
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[each.key].id
}
# Private
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.main_vpc.id
  tags     = { Name = "${var.prefix}-private-route-table-${each.key}" }
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
# Database
resource "aws_route_table" "database" {
  for_each = aws_subnet.database
  vpc_id   = aws_vpc.main_vpc.id
  tags     = { Name = "${var.prefix}-database-route-table-${each.key}" }
}
resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database[each.key].id
}

# Internet Gateway and Public Routes
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "${var.prefix}-igw" }
}
# Add route to Internet Gateway for public subnets
resource "aws_route" "public_to_igw" {
  for_each               = aws_route_table.public
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}

# NAT Gateways and Private Routes
resource "aws_eip" "ngw" {
  for_each = var.create_nat_gateway && !var.use_existing_eips ? aws_subnet.public : {}
  tags     = { Name = "${var.prefix}-public-subnet-${index(keys(aws_subnet.public), each.key)}-eip" }
}

locals {
  subnet_to_existing_eip_map = var.use_existing_eips ? zipmap([for subnet in aws_subnet.public : subnet.availability_zone], var.existing_eip_ids) : {}
}

resource "aws_nat_gateway" "ngw" {
  for_each      = var.create_nat_gateway ? aws_subnet.public : {}
  subnet_id     = each.value.id
  allocation_id = var.use_existing_eips ? local.subnet_to_existing_eip_map[each.key] : aws_eip.ngw[each.key].id
  tags          = { Name = "${var.prefix}-public-subnet-${each.key}-ngw" }
}
# Add route to NAT Gateway for private subnets
resource "aws_route" "private_to_ngw" {
  for_each               = var.create_nat_gateway ? aws_route_table.private : {}
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw[each.key].id
}

# VPC Endpoints
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values(aws_route_table.private)[*].id
  tags              = { Name = "${var.prefix}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_vpc_endpoints)
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  tags                = { Name = "${var.prefix}-${each.value}-endpoint" }
}

# Security Groups
resource "aws_security_group" "vpc_endpoint_sg" {
  name   = "${var.prefix}-vpc-endpoint-sg"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }
  tags = { Name = "${var.prefix}-vpc-endpoint-sg" }
}
