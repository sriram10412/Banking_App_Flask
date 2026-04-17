###############################################################################
# Module: codebuild
# CodeBuild project + IAM service role + GitHub webhook
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
    }
  }

  depends_on = [aws_codebuild_source_credential.github]

  tags = { Name = "${var.environment}-banking-codebuild" }
}

# ── Webhook (auto-build on push / PR targeting main) ─────────────────────────
resource "aws_codebuild_webhook" "banking" {
  project_name = aws_codebuild_project.banking.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }
    filter {
      type    = "HEAD_REF"
      pattern = "refs/heads/${var.github_branch}"
    }
  }

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED, PULL_REQUEST_REOPENED"
    }
    filter {
      type    = "BASE_REF"
      pattern = "refs/heads/${var.github_branch}"
    }
  }
}
