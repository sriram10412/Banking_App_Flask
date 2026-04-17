###############################################################################
# Module: codebuild – Variables
###############################################################################

variable "environment" {
  description = "Deployment environment (prod / staging)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. acme/my-app)"
  type        = string
}

variable "github_branch" {
  description = "Branch that triggers a build on push"
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub Personal Access Token (requires repo + admin:repo_hook scopes)"
  type        = string
  sensitive   = true
}

variable "db_password_secret_arn" {
  description = "Secrets Manager secret ARN whose value is the DB master password (injected as TF_VAR_db_password)"
  type        = string
}

variable "github_token_secret_arn" {
  description = "Secrets Manager secret ARN whose value is the GitHub PAT (injected as TF_VAR_github_token)"
  type        = string
}
