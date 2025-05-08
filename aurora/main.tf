# Variables
variable "prefix" {
  type = string
}

variable "name" {
  type        = string
  description = "Name of the resources"
}

variable "engine" {
  type        = string
  description = "Engine of the cluster. Must be one of aurora, aurora-mysql, or aurora-postgresql"
}

variable "engine_version" {
  type        = string
  description = "Engine version of the cluster"
}

variable "database_name" {
  type        = string
  description = "Name of the database to be created"
}

variable "master_username" {
  type        = string
  description = "Master username of the database"
}

variable "parameter_group_family" {
  type        = string
  description = "Parameter group family"
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of cloudwatch logs to export, e.g. audit, error, general, slowquery, iam-db-auth-error, postgresql"
}

variable "cluster_parameters" {
  type = list(
    object({
      name  = string
      value = string
    })
  )
  description = "Instance parameters"
}

variable "instance_count" {
  type        = number
  description = "Count of instances to be created for the cluster"
}

variable "instance_class" {
  type        = string
  description = "Class of instances to be created for the cluster"
}

variable "vpc_id" {
  type        = string
  description = "VPC's ID"
}

variable "ingress_allowed_security_groups" {
  type        = list(string)
  description = "List of security group names to allow access to the database"
}

variable "database_port" {
  type        = number
  description = "Port to expose to 'ingress_allowed_security_groups'"
}

variable "database_subnet_group_name" {
  type        = string
  description = "Name of database subnet group to associate the instances"
}

# variable "database_subnet_ids" {
#   type        = list(string)
#   description = "List of database subnet IDs"
# }

# Outputs
output "cluster_id" {
  value = aws_rds_cluster.main.id
}

# Resources

resource "aws_rds_cluster" "main" {
  cluster_identifier              = "${var.prefix}-${var.name}-cluster"
  engine                          = var.engine
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = "change_me"
  db_subnet_group_name            = var.database_subnet_group_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name
  vpc_security_group_ids          = [aws_security_group.main.id]
  final_snapshot_identifier       = "${var.prefix}-${var.name}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  backup_retention_period         = 35
  tags                            = { Name = "${var.prefix}-${var.name}-cluster" }
  lifecycle {
    ignore_changes = [final_snapshot_identifier, availability_zones]
  }
}

resource "aws_rds_cluster_parameter_group" "main" {
  name   = "${var.prefix}-${var.name}-cluster"
  family = var.parameter_group_family
  tags   = { Name = "${var.prefix}-${var.name}-cluster" }
  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }
}


resource "aws_rds_cluster_instance" "main" {
  count                        = var.instance_count
  identifier                   = "${var.prefix}-${var.name}-${count.index}"
  instance_class               = var.instance_class
  cluster_identifier           = aws_rds_cluster.main.id
  engine                       = var.engine
  engine_version               = var.engine_version
  db_subnet_group_name         = var.database_subnet_group_name
  db_parameter_group_name      = aws_db_parameter_group.main.name
  promotion_tier               = count.index
  performance_insights_enabled = false # not supported for old db instance class / engine
  apply_immediately            = true
  tags                         = { Name = "${var.prefix}-${var.name}-${count.index}" }
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.prefix}-${var.name}"
  family = var.parameter_group_family
  tags   = { Name = "${var.prefix}-${var.name}" }
}


resource "aws_security_group" "main" {
  name   = "${var.prefix}-${var.name}-sg"
  vpc_id = var.vpc_id
  tags   = { Name = "${var.prefix}-${var.name}-sg" }
  ingress {
    from_port       = var.database_port
    to_port         = var.database_port
    protocol        = "tcp"
    security_groups = var.ingress_allowed_security_groups
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

