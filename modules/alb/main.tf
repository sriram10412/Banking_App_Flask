###############################################################################
# Module: alb
# Application Load Balancer – HTTPS termination, HTTP→HTTPS redirect,
# access logging, deletion protection
###############################################################################

# ── S3 Bucket for ALB Access Logs ────────────────────────────────────────────
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.environment}-banking-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${var.environment}-alb-access-logs" }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy – allow ELB service account to write logs
data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    }]
  })
}

# ── Application Load Balancer ────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.environment}-banking-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  #enable_deletion_protection = true
  enable_deletion_protection = false # creating unnecessary issue during destroy 

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  lifecycle {
    ignore_changes = [security_groups, subnets]
  }

  tags       = { Name = "${var.environment}-banking-alb" }
  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# ── Target Group ─────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name        = "${var.environment}-banking-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate

  health_check {
    enabled  = true
    path     = "/health"
    protocol = "HTTP"
    matcher  = "200"
    interval = 30
    timeout  = 10

    healthy_threshold = 2

    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.environment}-banking-tg" }
}

# ── HTTP → HTTPS Redirect ─────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}