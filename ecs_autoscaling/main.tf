# Variables
variable "prefix" { type = string }

variable "name" { type = string }

variable "ecs_cluster_name" { type = string }

variable "ecs_service_name" { type = string }

variable "alb_arn" { type = string }

variable "alb_target_group_arn" { type = string }

variable "min_capacity" { type = number }

variable "max_capacity" { type = number }

# Resources

resource "aws_appautoscaling_target" "main" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  tags               = { Name = "${var.prefix}-${var.name}-ecs-autoscaling-target" }
}

resource "aws_appautoscaling_policy" "gradual" {
  name               = "${var.prefix}-${var.name}-gradual-scale-out"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace
  policy_type        = "TargetTrackingScaling"
  depends_on         = [aws_appautoscaling_target.main]
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 28
    scale_in_cooldown  = 60
    scale_out_cooldown = 30
  }
}

resource "aws_appautoscaling_policy" "spike" {
  name               = "${var.prefix}-${var.name}-spike-scale-out"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace
  policy_type        = "StepScaling"
  depends_on         = [aws_appautoscaling_target.main]
  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 30
    metric_aggregation_type = "Maximum"
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 700
      scaling_adjustment          = 3
    }
    step_adjustment {
      metric_interval_lower_bound = 700
      metric_interval_upper_bound = 1400
      scaling_adjustment          = 4
    }
    step_adjustment {
      metric_interval_lower_bound = 1400
      scaling_adjustment          = 5
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "spike" {
  alarm_name          = "${var.prefix}-${var.name}-spike-scale-out"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCountPerTarget"
  period              = "60"
  statistic           = "Sum"
  threshold           = 1000
  dimensions = {
    TargetGroup  = "targetgroup/${split("targetgroup/", var.alb_target_group_arn)[1]}"
    LoadBalancer = split("loadbalancer/", var.alb_arn)[1]
  }
  alarm_actions = [aws_appautoscaling_policy.spike.arn]
  tags          = { Name = "${var.prefix}-${var.name}-spike-scale-out-alarm" }
}
