# Banking App – AWS Infrastructure

## Architecture

```
Internet → ALB (HTTP:80) → ECS Fargate (port 8080) → RDS PostgreSQL
                                    ↑
                               ECR (Docker images)
                                    ↑
                          CodeBuild (CI/CD builds)
                                    ↑
                          GitHub Webhook (auto-trigger)
```

## Pipeline Flow

### Infrastructure Bootstrap (GitHub Actions)
```
Push to main (terraform/infra changes)
     ↓
bootstrap job  → creates S3, DynamoDB, Secrets Manager via bootstrap.sh
     ↓
Terraform Init → Init + Format Check + Validate
     ↓
Terraform Plan → plans infra changes
     ↓
Terraform Apply → creates VPC, RDS, ECS, ALB, ECR, CodeBuild, IAM, Monitoring
     ↓
approve-destroy (pauses, waits for manual approval via GitHub Issue comment)
     ↓  (comment "approved" on the issue)
Terraform Destroy → tears down all infrastructure
```

### App Build & Deploy (AWS CodeBuild — auto-triggered on every push to main)
```
Push to main
     ↓
GitHub webhook → triggers CodeBuild automatically
     ↓
buildspec.yml → build Docker image → push to ECR → deploy to ECS
```

## Terraform Modules

| Module | Resources Created |
|--------|-------------------|
| `vpc` | VPC, public/private subnets, route tables, NAT gateway, VPC flow logs |
| `security` | Security groups for ALB, ECS, RDS |
| `iam` | ECS task execution role, ECS task role, CodeBuild role |
| `ecr` | ECR repository for Docker images |
| `rds` | PostgreSQL RDS instance, subnet group, parameter group, Secrets Manager credentials |
| `alb` | Application Load Balancer, target group, listener, S3 access logs bucket |
| `ecs` | ECS cluster, Fargate task definition, ECS service |
| `codebuild` | CodeBuild project, GitHub webhook, CloudWatch log group |
| `monitoring` | CloudWatch alarms for ECS, ALB, RDS |

## Setup

### Step 1 — Add GitHub Secrets

Go to **GitHub → Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | `603196661038` |
| `AWS_DEFAULT_REGION` | `ap-southeast-1` |
| `TF_STATE_BUCKET` | `banking-app-tfstate` |
| `TF_VAR_DB_PASSWORD` | RDS master password (no `/`, `@`, `"`, spaces) |
| `GH_PAT` | GitHub PAT with `repo` + `admin:repo_hook` scopes |

### Step 2 — Push to trigger bootstrap

```bash
git push origin main
```

This runs the GitHub Actions bootstrap job which:
1. Creates S3 bucket, DynamoDB table, and Secrets Manager secrets via `bootstrap.sh`
2. Runs `terraform apply` to provision all AWS infrastructure
3. Registers a GitHub webhook on the repo — CodeBuild will auto-trigger from now on

### Step 3 — All future pushes auto-trigger CodeBuild

```bash
git push origin main  # CodeBuild builds, pushes to ECR, deploys to ECS automatically
```

## Sensitive Variables

`db_password` and `github_token` are **not passed as Terraform variables**. They are read directly from AWS Secrets Manager at runtime using data sources:

```
prod/banking-app/db-master-password  →  used by RDS + CodeBuild
prod/banking-app/github-token        →  used by CodeBuild webhook
```

These secrets are created by `bootstrap.sh` before Terraform runs.

## Destroying Infrastructure

To destroy all AWS infrastructure:

1. Push to `main` to trigger the pipeline
2. After the bootstrap job completes, the `approve-destroy` stage opens a GitHub Issue
3. Comment `approved` on the issue
4. The `destroy` job runs `terraform destroy` and tears down everything

## API Endpoints

```bash
ALB="http://<alb-dns-name>"

curl ${ALB}/health

curl -X POST ${ALB}/accounts \
  -H "Content-Type: application/json" \
  -d '{"account_id":"ACC001","owner_name":"Alice","initial_balance":"1000.00"}'

curl ${ALB}/accounts/ACC001/balance

curl -X POST ${ALB}/accounts/ACC001/deposit \
  -H "Content-Type: application/json" \
  -d '{"amount":"500.00"}'

curl -X POST ${ALB}/accounts/ACC001/withdraw \
  -H "Content-Type: application/json" \
  -d '{"amount":"200.00"}'
```

## Project Structure

```
.
├── .github/workflows/pipeline.yml   # GitHub Actions bootstrap + destroy pipeline
├── modules/
│   ├── alb/                         # Application Load Balancer
│   ├── codebuild/                   # CodeBuild project + GitHub webhook
│   ├── ecr/                         # ECR repository
│   ├── ecs/                         # ECS Fargate cluster + service
│   ├── iam/                         # IAM roles and policies
│   ├── monitoring/                  # CloudWatch alarms
│   ├── rds/                         # RDS PostgreSQL
│   ├── security/                    # Security groups
│   └── vpc/                         # VPC and networking
├── environments/prod/
│   └── terraform.tfvars             # Production variable values
├── app/                             # Flask application source
├── bootstrap.sh                     # Creates S3, DynamoDB, Secrets Manager
├── buildspec.yml                    # CodeBuild build specification
├── Dockerfile                       # Docker image definition
├── main.tf                          # Root Terraform config
├── variables.tf                     # Root variable declarations
└── outputs.tf                       # Root outputs
```
