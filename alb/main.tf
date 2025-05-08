# Variables

variable "prefix" { type = string }

variable "name" { type = string }

variable "vpc_id" { type = string }

variable "alb_subnets" { type = list(string) }

variable "ssl_policy" { type = string }

variable "certificate_arn" { type = string }

variable "application_configuration" {
  type = object({
    protocol = string
    port     = number
    health_check = object({
      path     = string
      port     = number
      protocol = string
    })
  })
}

variable "blue_green_enabled" { type = bool }

# Outputs

output "alb_arn" { value = aws_lb.main.arn }

output "alb_listener_arn" { value = aws_lb_listener.main.arn }

output "alb_target_groups" { value = aws_lb_target_group.main }

output "alb_security_group" { value = aws_security_group.main }

# Load Balancer
resource "aws_lb" "main" {
  name               = "${var.prefix}-${var.name}"
  subnets            = var.alb_subnets
  security_groups    = [aws_security_group.main.id]
  internal           = true
  load_balancer_type = "application"
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }
  tags       = { Name = "${var.prefix}-${var.name}-alb" }
  depends_on = [aws_s3_bucket.alb_logs]
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443 #var.application_configuration.port
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = var.blue_green_enabled ? aws_lb_target_group.main["blue"].arn : aws_lb_target_group.main["main"].arn
  }
  #   mutual_authentication {
  #     ignore_client_certificate_expiry = false
  #     mode                             = "off"
  #   }
  lifecycle {
    ignore_changes = [default_action]
  }
  tags = { Name = "${var.prefix}-${var.name}-alb-listener" }
}


resource "aws_lb_target_group" "main" {
  for_each             = var.blue_green_enabled ? toset(["blue", "green"]) : toset(["main"])
  name                 = "${var.prefix}-${var.name}-${each.value}"
  vpc_id               = var.vpc_id
  port                 = var.application_configuration.port
  protocol             = var.application_configuration.protocol
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path     = var.application_configuration.health_check.path
    port     = var.application_configuration.health_check.port
    protocol = var.application_configuration.health_check.protocol
    timeout  = 60
    interval = 90
  }
  tags = { Name = "${var.prefix}-${var.name}-${each.value}-alb-target-group" }
}

# Security Group

resource "aws_security_group" "main" {
  name   = "${var.prefix}-${var.name}-alb-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = { Name = "${var.prefix}-${var.name}-alb-sg" }
}

# Logs Bucket

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.prefix}-alb-logs"
  force_destroy = false
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "alb-logs-expiration"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 60 }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}
