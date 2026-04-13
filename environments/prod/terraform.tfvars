###############################################################################
# environments/prod/terraform.tfvars
###############################################################################

aws_region     = "ap-southeast-1"
aws_account_id = "603196661038"
environment    = "prod"

# Networking
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database (set db_password via: export TF_VAR_db_password=...)
db_name           = "bankingdb"
db_username       = "banking_admin"
db_password       = "REPLACE_ME_USE_ENV_VAR"
db_instance_class = "db.t3.micro"

# ECS
ecs_desired_count = 2
ecs_cpu           = 512
ecs_memory        = 1024
app_image_tag     = "latest"

# GitLab CI OIDC – exact project path from gitlab.com URL
#gitlab_project_path = "ram10412aws-group/banking_app_flask"

# Alerting