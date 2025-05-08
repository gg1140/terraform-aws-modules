# Variables

variable "prefix" { type = string }

variable "name" { type = string }

variable "vpc_id" { type = string }

variable "subnet_ids" { type = list(string) }

variable "container_name" { type = string }

variable "container_port" { type = number }

variable "container_cpu" { type = number }

variable "deployment_controller_type" { type = string }

variable "alb_target_group_arn" {
  type    = string
  default = null
}

variable "assign_public_ip" {
  type    = bool
  default = false
}

variable "on_demand_instance_weight" {
  type    = number
  default = 1
}

variable "spot_instance_weight" {
  type    = number
  default = 1
}

variable "task_role_policies" {
  type = list(object({
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "alb_security_group_id" {
  type    = string
  default = null
}

# Outputs

output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }

output "ecs_service_name" { value = aws_ecs_service.main.name }

output "security_group_id" { value = aws_security_group.main.id }

# Resources

## API Server
### Jump Server
### Load Balancer
### Logging
### S3 Buckets
# DataBase
# Secrets Params
# IAM Roles and Policies

# Elastic Container Service: Cluster

resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-${var.name}"
  tags = { Name = "${var.prefix}-${var.name}" }
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# resource "aws_ecs_cluster_capacity_providers" "main" {
#   cluster_name       = aws_ecs_cluster.main.name
#   capacity_providers = ["FARGATE", "FARGATE_SPOT"]
#   default_capacity_provider_strategy {
#     capacity_provider = "FARGATE"
#     base              = 0
#     weight            = var.on_demand_instance_weight
#   }
#   default_capacity_provider_strategy {
#     capacity_provider = "FARGATE_SPOT"
#     base              = 0
#     weight            = var.spot_instance_weight
#   }
# }

# Elastic Container Service: Service

resource "aws_ecs_service" "main" {
  name                   = "${var.prefix}-${var.name}"
  cluster                = aws_ecs_cluster.main.name
  enable_execute_command = true
  desired_count          = 0
  task_definition        = aws_ecs_task_definition.initial_task.arn
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = var.assign_public_ip
  }
  deployment_controller {
    type = var.deployment_controller_type
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = var.on_demand_instance_weight
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = var.spot_instance_weight
  }
  dynamic "load_balancer" {
    for_each = var.alb_target_group_arn != null ? toset([var.alb_target_group_arn]) : toset([])
    content {
      target_group_arn = load_balancer.value
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition,
      load_balancer,
      capacity_provider_strategy,
    ]
  }
  tags = { Name = "${var.prefix}-${var.name}-ecs-service" }
}

# Initial Task Definition with Python HTTP Server (for verification)
resource "aws_ecs_task_definition" "initial_task" {
  family             = "${var.prefix}-${var.name}"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_exec_role.arn
  task_role_arn      = aws_iam_role.task_role.arn
  cpu                = 256
  memory             = 512
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = "python:latest" # Specify the Python image
    essential = true
    portMappings = var.container_port != null ? [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }] : []
    # command = ["python", "-m", "http.server", tostring(var.container_port)] # The command to run
  }])
  lifecycle { ignore_changes = all }
  tags = { Name = "${var.prefix}-${var.name}-initial-task" }
}

# Execution Role

resource "aws_iam_role" "ecs_exec_role" {
  name               = "${var.prefix}-${var.name}-ecs-exec-role"
  description        = "ECS Exec Role"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_exec_role_policy_document.json
  tags               = { Name = "${var.prefix}-${var.name}-ecs-exec-role" }
}

resource "aws_iam_policy" "ecs_exec_role_policy" {
  name        = "${var.prefix}-${var.name}-ecs-exec-role-policy"
  description = "ECS Exec Role Policy"
  policy      = data.aws_iam_policy_document.ecs_exec_role_policy_document.json
  tags        = { Name = "${var.prefix}-${var.name}-ecs-exec-role-policy" }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy_attachment" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = aws_iam_policy.ecs_exec_role_policy.arn
}

data "aws_iam_policy_document" "ecs_exec_role_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
  # KMS, Parameter Store, Secrets Manager
}

data "aws_iam_policy_document" "assume_ecs_exec_role_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task Role

resource "aws_iam_role" "task_role" {
  name               = "${var.prefix}-${var.name}-task-role"
  description        = "Task Role"
  assume_role_policy = data.aws_iam_policy_document.assume_task_role_policy_document.json
  tags               = { Name = "${var.prefix}-${var.name}-task-role" }
}

resource "aws_iam_policy" "task_role_policy" {
  name        = "${var.prefix}-${var.name}-task-role-policy"
  description = "Task Role Policy"
  policy      = data.aws_iam_policy_document.task_role_policy_document.json
  tags        = { Name = "${var.prefix}-${var.name}-task-role-policy" }
}

resource "aws_iam_role_policy_attachment" "task_role_policy_attachment" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.task_role_policy.arn
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "task_role_policy_document" {
  # # enable EventBridge
  # statement {
  #   effect    = "Allow"
  #   actions   = ["events:PutTargets", "events:RemoveTargets", "events:ListRules", "eveil" "events:PutRule", "events:DeleteRule"]
  #   resources = ["arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.prefix}-*"]
  # }
  # Additional Policies
  dynamic "statement" {
    for_each = toset(var.task_role_policies)
    content {
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

data "aws_iam_policy_document" "assume_task_role_policy_document" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Security Groups
resource "aws_security_group" "main" {
  name   = "${var.prefix}-${var.name}-sg"
  vpc_id = var.vpc_id
  dynamic "ingress" {
    for_each = var.alb_security_group_id != null ? toset([var.alb_security_group_id]) : toset([])
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = { Name = "${var.prefix}-${var.name}-sg" }
}
