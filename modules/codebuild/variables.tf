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

variable "db_password" {
  description = "Database master password – stored in Secrets Manager by bootstrap.sh and fetched in buildspec"
  type        = string
  sensitive   = true
}

variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}
