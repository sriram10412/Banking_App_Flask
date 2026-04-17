#!/bin/bash
###############################################################################
# bootstrap.sh – Idempotent prereq setup (runs in CodeBuild install phase)
#
# Creates prerequisites that must exist before Terraform can run:
#   1. S3 bucket  – Terraform remote state
#   2. DynamoDB   – Terraform state lock
#   3. Secrets Manager secret – DB master password  (from $DB_PASSWORD env var)
#   4. Secrets Manager secret – GitHub token        (from $GITHUB_TOKEN env var)
#
# Safe to run on every build — all operations are idempotent.
###############################################################################
set -euo pipefail

ACCOUNT_ID="842548752774"
REGION="us-east-1"
BUCKET_NAME="bankingpromo1234"
DB_SECRET_NAME="prod/banking-app/db-master-password"
GH_SECRET_NAME="prod/banking-app/github-token"

echo "======================================"
echo " Banking App Bootstrap (CodeBuild)"
echo " Account : ${ACCOUNT_ID}"
echo " Region  : ${REGION}"
echo "======================================"

# ── 1. S3 state bucket ────────────────────────────────────────────────────────
echo ""
echo "[1/4] S3 state bucket..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "  Already exists — skipping configuration."
else
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
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
  echo "  Created and configured."
fi

# ── 2. DynamoDB lock table ─────────────────────────────────────────────────────
echo ""
echo "[2/4] DynamoDB lock table..."
aws dynamodb create-table \
  --table-name banking-app-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" 2>/dev/null \
  && echo "  Created" || echo "  Already exists"

# ── 3. Secrets Manager – DB master password ────────────────────────────────────
echo ""
echo "[3/4] Secrets Manager secret for DB password..."

if [ -z "${DB_PASSWORD:-}" ]; then
  echo "  ERROR: DB_PASSWORD env var is not set."
  exit 1
fi

aws secretsmanager create-secret \
  --name "${DB_SECRET_NAME}" \
  --description "Banking App RDS master password" \
  --secret-string "${DB_PASSWORD}" \
  --region "${REGION}" \
  --query 'ARN' --output text 2>/dev/null \
  && echo "  Secret created." \
  || {
    aws secretsmanager put-secret-value \
      --secret-id "${DB_SECRET_NAME}" \
      --secret-string "${DB_PASSWORD}" \
      --region "${REGION}" > /dev/null
    echo "  Secret already exists – value updated."
  }

# ── 4. Secrets Manager – GitHub token ─────────────────────────────────────────
echo ""
echo "[4/4] Secrets Manager secret for GitHub token..."

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "  ERROR: GITHUB_TOKEN env var is not set."
  exit 1
fi

aws secretsmanager create-secret \
  --name "${GH_SECRET_NAME}" \
  --description "Banking App GitHub PAT" \
  --secret-string "${GITHUB_TOKEN}" \
  --region "${REGION}" \
  --query 'ARN' --output text 2>/dev/null \
  && echo "  Secret created." \
  || {
    aws secretsmanager put-secret-value \
      --secret-id "${GH_SECRET_NAME}" \
      --secret-string "${GITHUB_TOKEN}" \
      --region "${REGION}" > /dev/null
    echo "  Secret already exists – value updated."
  }

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================"
echo " Bootstrap complete."
echo "======================================"
