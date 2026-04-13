# Banking App – AWS Infrastructure (GitHub Actions)

## Architecture

```
Internet → ALB (HTTP:80) → ECS Fargate (port 8080) → RDS PostgreSQL
                                    ↑
                               ECR (Docker images)
```

## Pipeline Flow

```
push to main
     ↓
bootstrap    → creates OIDC, S3, DynamoDB, IAM role (skips if exists)
     ↓
terraform-plan   → auto
     ↓
terraform-apply  → requires manual approval (GitHub Environment protection)
     ↓
lint + build + test + security  → run in parallel
     ↓
deploy-ecs   → ECS rolling deploy (auto)
     ↓
smoke-test   → hits /health → prints live URL
```

## Setup

### Step 1 — Run bootstrap locally

```bash
# Edit bootstrap.sh and set your GitHub repo
vim bootstrap.sh  # set GITHUB_REPO="your-username/banking_app_flask"

chmod +x bootstrap.sh
./bootstrap.sh
```

### Step 2 — Add GitHub Secrets

Go to **GitHub → Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | printed by bootstrap.sh |
| `AWS_ACCOUNT_ID` | your 12-digit AWS account ID |
| `AWS_DEFAULT_REGION` | `ap-southeast-1` |
| `AWS_ACCESS_KEY_ID` | your IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | your IAM user secret key |
| `ECS_CLUSTER_NAME` | `prod-banking-cluster` |
| `ECS_SERVICE_NAME` | `prod-banking-service` |
| `TF_VAR_DB_PASSWORD` | your RDS password |

### Step 3 — Create GitHub Environments

Go to **GitHub → Settings → Environments** and create:

- `production` — add required reviewers for terraform apply approval
- `destroy` — add required reviewers for destroy approval

### Step 4 — Push to trigger pipeline

```bash
git add .
git commit -m "initial commit"
git push origin main
```

## API Endpoints

```bash
ALB="http://<alb-dns-from-pipeline-output>"

curl ${ALB}/health
curl -X POST ${ALB}/accounts -H "Content-Type: application/json" \
  -d '{"account_id":"ACC001","owner_name":"Alice","initial_balance":"1000.00"}'
curl ${ALB}/accounts/ACC001/balance
curl -X POST ${ALB}/accounts/ACC001/deposit -H "Content-Type: application/json" \
  -d '{"amount":"500.00"}'
curl -X POST ${ALB}/accounts/ACC001/withdraw -H "Content-Type: application/json" \
  -d '{"amount":"200.00"}'
```

## Key Differences from GitLab

| Feature | GitLab | GitHub |
|---------|--------|--------|
| CI file | `.gitlab-ci.yml` | `.github/workflows/pipeline.yml` |
| OIDC provider | `gitlab.com` | `token.actions.githubusercontent.com` |
| Manual approval | `when: manual` | GitHub Environment protection rules |
| Artifacts | `artifacts:` | `actions/upload-artifact` |
| Variables | CI/CD Variables | Repository Secrets |
| Role name | `prod-gitlab-ci-role` | `prod-github-ci-role` |
