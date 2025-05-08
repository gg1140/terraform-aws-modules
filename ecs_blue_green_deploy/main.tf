# Variables
variable "prefix" { type = string }

variable "name" { type = string }

variable "deployment_config_name" { type = string }

variable "terminate_wait_time_in_minutes" { type = number }

variable "ecs_cluster_name" { type = string }

variable "ecs_service_name" { type = string }

variable "alb_listener_arn" { type = string }

variable "blue_alb_target_group_name" { type = string }

variable "green_alb_target_group_name" { type = string }

# Code Deploy
resource "aws_codedeploy_app" "main" {
  name             = "${var.prefix}-${var.name}"
  compute_platform = "ECS"
  tags             = { Name = "${var.prefix}-${var.name}-blue-green-deploy" }
}

resource "aws_codedeploy_deployment_group" "main" {
  app_name               = aws_codedeploy_app.main.name
  service_role_arn       = aws_iam_role.main.arn
  deployment_group_name  = "${var.prefix}-${var.name}"
  deployment_config_name = var.deployment_config_name
  # TODO: Add target group
  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.terminate_wait_time_in_minutes
    }
  }
  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route { listener_arns = [var.alb_listener_arn] }
      target_group { name = var.blue_alb_target_group_name }
      target_group { name = var.green_alb_target_group_name }
    }
  }
  tags = { Name = "${var.prefix}-${var.name}-blue-green-deploy" }
}

# IAMs
resource "aws_iam_role" "main" {
  name               = "${var.prefix}-${var.name}-blue-green-deploy"
  assume_role_policy = data.aws_iam_policy_document.main.json
  tags               = { Name = "${var.prefix}-${var.name}-blue-green-deploy" }
}

resource "aws_iam_role_policy_attachment" "main" {
  role       = aws_iam_role.main.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

data "aws_iam_policy_document" "main" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

