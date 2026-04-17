###############################################################################
# environments/prod/terraform.tfvars
###############################################################################

aws_region     = "us-east-1"
aws_account_id = "842548752774"
environment    = "prod"

# Networking
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database
# db_password is NOT stored here – it is injected at runtime:
#   - CodeBuild injects TF_VAR_db_password from Secrets Manager
#   - For local runs: export TF_VAR_db_password=<password>
db_name           = "bankingdb"
db_username       = "banking_admin"
db_instance_class = "db.t3.micro"

# ECS
ecs_desired_count = 1
ecs_cpu           = 512
ecs_memory        = 1024
app_image_tag     = "latest"

# CodeBuild / CI
github_repo   = "sriram10412/Banking_App_Flask"
github_branch = "main"
# github_token is sensitive – pass via: export TF_VAR_github_token=<PAT>
# db_password_secret_arn is printed by bootstrap.sh – fill in after running it:
db_password_secret_arn  = "arn:aws:secretsmanager:us-east-1:842548752774:secret:prod/banking-app/db-master-password-eZfMp5"
github_token_secret_arn = "arn:aws:secretsmanager:us-east-1:842548752774:secret:prod/banking-app/github-token-jmKeQz"
