###############################################################################
# Banking App – Root Configuration
# Orchestrates all child modules
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state – update bucket/key/region before first run
  backend "s3" {
    bucket         = "banking-app-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "banking-app-tfstate-lock"
  }
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/banking-app/db-master-password"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "prod/banking-app/github-token"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "banking-app"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Import pre-existing CloudWatch log groups that were created outside Terraform
import {
  to = module.codebuild.aws_cloudwatch_log_group.codebuild
  id = "/codebuild/prod-banking"
}

import {
  to = module.vpc.aws_cloudwatch_log_group.flow_logs
  id = "/aws/vpc/prod-banking-flow-logs"
}

# ── VPC ──────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── Security Groups ───────────────────────────────────────────────────────────
module "security" {
  source = "./modules/security"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = var.vpc_cidr
}

# ── IAM Roles & Policies ─────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  environment    = var.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
}

# ── ECR Repository ────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  environment     = var.environment
  repository_name = "banking-app"
}

# ── RDS (PostgreSQL) ─────────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.security.rds_sg_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = data.aws_secretsmanager_secret_version.db_password.secret_string
  db_instance_class     = var.db_instance_class
}

# ── ALB ───────────────────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_sg_id
}

# ── ECS (Fargate) ─────────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  environment             = var.environment
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  ecs_security_group_id   = module.security.ecs_sg_id
  alb_target_group_arn    = module.alb.target_group_arn
  ecr_repository_url      = module.ecr.repository_url
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  db_host                 = module.rds.db_endpoint
  db_name                 = var.db_name
  db_username             = var.db_username
  db_secret_arn           = module.rds.db_secret_arn
  desired_count           = var.ecs_desired_count
  cpu                     = var.ecs_cpu
  memory                  = var.ecs_memory
  app_image_tag           = var.app_image_tag
}

# ── CodeBuild (CI/CD Pipeline) ───────────────────────────────────────────────
module "codebuild" {
  source = "./modules/codebuild"

  environment     = var.environment
  aws_region      = var.aws_region
  aws_account_id  = var.aws_account_id
  github_repo     = var.github_repo
  github_branch   = var.github_branch
  github_token    = data.aws_secretsmanager_secret_version.github_token.secret_string
  db_password     = data.aws_secretsmanager_secret_version.db_password.secret_string
  tf_state_bucket = var.tf_state_bucket
}

# ── Monitoring & Logging ─────────────────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  environment      = var.environment
  aws_region       = var.aws_region
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  alb_arn_suffix   = module.alb.alb_arn_suffix
  rds_identifier   = module.rds.db_identifier
}
