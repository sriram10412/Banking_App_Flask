###############################################################################
# Module: codebuild – Outputs
###############################################################################

output "project_name" {
  description = "CodeBuild project name"
  value       = aws_codebuild_project.banking.name
}

output "project_arn" {
  description = "CodeBuild project ARN"
  value       = aws_codebuild_project.banking.arn
}

output "service_role_arn" {
  description = "IAM role ARN used by CodeBuild"
  value       = aws_iam_role.codebuild.arn
}

