###############################################################################
# Module: codebuild
# CodeBuild project + IAM service role + GitHub webhook
# 
# NOTE: This module CREATES the CodeBuild project and webhook.
# After creation, GitHub will automatically trigger builds on push/PR.
# No need for GitHub Actions to manually start builds.
###############################################################################

# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codebuild" {
  name = "${var.environment}-banking-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.environment}-banking-codebuild-role" }
}

# CodeBuild provisions all infrastructure via Terraform, so it needs broad access
resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── GitHub Source Credentials ─────────────────────────────────────────────────
# One credential per account/region/server-type – shared across all projects
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}

# ── CodeBuild Project ─────────────────────────────────────────────────────────
resource "aws_codebuild_project" "banking" {
  name          = "${var.environment}-banking-codebuild"
  description   = "CI/CD pipeline for Banking App Flask"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_repo}.git"
    git_clone_depth = 1
    buildspec       = "buildspec.yml"

    git_submodules_config {
      fetch_submodules = false
    }
  }

  source_version = var.github_branch

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    # Docker-in-Docker requires privileged mode
    privileged_mode = true

    # Environment variables for buildspec.yml
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_NAME"
      value = "${var.environment}-banking-app"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECS_CLUSTER_NAME"
      value = "${var.environment}-banking-cluster"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ECS_SERVICE_NAME"
      value = "${var.environment}-banking-service"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ALB_NAME"
      value = "${var.environment}-banking-alb"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = var.tf_state_bucket
      type  = "PLAINTEXT"
    }

    # ⚠️ SECURITY NOTE: These are sensitive and should ideally be stored in Secrets Manager
    # For now keeping in PLAINTEXT as per original config, but consider moving to PARAMETER_STORE
    environment_variable {
      name  = "DB_PASSWORD"
      value = var.db_password
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GH_PAT"
      value = var.github_token
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.environment}-banking"
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  depends_on = [aws_codebuild_source_credential.github]

  tags = {
    Name        = "${var.environment}-banking-codebuild"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ── CloudWatch Log Group for CodeBuild ────────────────────────────────────────
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/codebuild/${var.environment}-banking"
  retention_in_days = 7
  skip_destroy      = true # Prevent deletion on terraform destroy

  tags = {
    Name        = "${var.environment}-banking-codebuild-logs"
    Environment = var.environment
  }
}

# ── GitHub Webhook (Auto-trigger on push to main branch) ──────────────────────
# After this webhook is created, GitHub will automatically call CodeBuild when:
#   1. Code is pushed to the main branch
#   2. Pull requests are created/updated/reopened targeting main
resource "aws_codebuild_webhook" "banking" {
  project_name = aws_codebuild_project.banking.name
  build_type   = "BUILD"

  # Filter group 1: Trigger on PUSH to main branch
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/${var.github_branch}$"
    }
  }

  # Filter group 2: Trigger on PR operations targeting main branch
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED, PULL_REQUEST_REOPENED"
    }

    filter {
      type    = "BASE_REF"
      pattern = "^refs/heads/${var.github_branch}$"
    }
  }

  depends_on = [aws_codebuild_project.banking]
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.banking.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.banking.arn
}

output "codebuild_webhook_url" {
  description = "Webhook URL (registered with GitHub)"
  value       = aws_codebuild_webhook.banking.payload_url
  sensitive   = true
}

output "codebuild_log_group_name" {
  description = "CloudWatch log group name for CodeBuild logs"
  value       = aws_cloudwatch_log_group.codebuild.name
}