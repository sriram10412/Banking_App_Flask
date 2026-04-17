#!/bin/bash
###############################################################################
# bootstrap.sh – Run ONCE locally before the first Terraform apply
#
# Creates prerequisites that must exist before Terraform can run:
#   1. S3 bucket  – Terraform remote state
#   2. DynamoDB   – Terraform state lock
#   3. Secrets Manager secret – DB master password (referenced by CodeBuild)
#
# After this script succeeds:
#   1. Copy the printed db_password_secret_arn into terraform.tfvars
#   2. export TF_VAR_github_token=<your-PAT>
#   3. export TF_VAR_db_password=<your-db-password>   (same value stored above)
#   4. terraform init && terraform apply -var-file="environments/prod/terraform.tfvars"
#      → This creates ALL infrastructure including the CodeBuild project.
#   5. Push to main – CodeBuild webhook triggers the pipeline automatically.
###############################################################################
set -euo pipefail

ACCOUNT_ID="842548752774"
REGION="us-east-1"
BUCKET_NAME="bankingpromo1234"
SECRET_NAME="prod/banking-app/db-master-password"

echo "======================================"
echo " Banking App Bootstrap (CodeBuild)"
echo " Account : ${ACCOUNT_ID}"
echo " Region  : ${REGION}"
echo "======================================"

# ── 1. S3 state bucket ────────────────────────────────────────────────────────
echo ""
echo "[1/3] S3 state bucket..."
# us-east-1 is the S3 default – LocationConstraint must be omitted for it
if [ "${REGION}" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null \
    && echo "  Created" || echo "  Already exists"
else
  aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" 2>/dev/null \
    && echo "  Created" || echo "  Already exists"
fi

aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "  S3 bucket ready."

# ── 2. DynamoDB lock table ─────────────────────────────────────────────────────
echo ""
echo "[2/3] DynamoDB lock table..."
aws dynamodb create-table \
  --table-name banking-app-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" 2>/dev/null \
  && echo "  Created" || echo "  Already exists"

# ── 3. Secrets Manager – DB master password ────────────────────────────────────
echo ""
echo "[3/3] Secrets Manager secret for DB password..."

if [ -z "${TF_VAR_db_password:-}" ]; then
  echo ""
  echo "  ERROR: TF_VAR_db_password is not set."
  echo "  Export it before running bootstrap:"
  echo "    export TF_VAR_db_password='<your-secure-password>'"
  exit 1
fi

SECRET_ARN=$(aws secretsmanager create-secret \
  --name "${SECRET_NAME}" \
  --description "Banking App RDS master password (used by CodeBuild as TF_VAR_db_password)" \
  --secret-string "${TF_VAR_db_password}" \
  --region "${REGION}" \
  --query 'ARN' \
  --output text 2>/dev/null) \
  && echo "  Secret created." \
  || {
    # Secret already exists – update its value
    SECRET_ARN=$(aws secretsmanager put-secret-value \
      --secret-id "${SECRET_NAME}" \
      --secret-string "${TF_VAR_db_password}" \
      --region "${REGION}" \
      --query 'ARN' \
      --output text)
    echo "  Secret already exists – value updated."
  }

# Retrieve ARN in case the create path set it, put-secret-value path doesn't
if [ -z "${SECRET_ARN:-}" ]; then
  SECRET_ARN=$(aws secretsmanager describe-secret \
    --secret-id "${SECRET_NAME}" \
    --region "${REGION}" \
    --query 'ARN' \
    --output text)
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================"
echo " Bootstrap complete! Next steps:"
echo "======================================"
echo ""
echo "  1. Fill in terraform.tfvars:"
echo "       db_password_secret_arn = \"${SECRET_ARN}\""
echo ""
echo "  2. Create a GitHub PAT with scopes: repo, admin:repo_hook"
echo "     https://github.com/settings/tokens/new"
echo ""
echo "  3. Run the first Terraform apply:"
echo ""
echo "       export TF_VAR_github_token='<your-PAT>'"
echo "       export TF_VAR_db_password='${TF_VAR_db_password}'"
echo "       terraform init"
echo "       terraform apply -var-file=\"environments/prod/terraform.tfvars\""
echo ""
echo "     This creates all infrastructure AND the CodeBuild project."
echo ""
echo "  4. Push to the main branch – the CodeBuild webhook will trigger"
echo "     the pipeline automatically on every subsequent push."
echo ""
