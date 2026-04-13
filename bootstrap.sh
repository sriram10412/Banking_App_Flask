#!/bin/bash
###############################################################################
# bootstrap.sh – Run ONCE locally before pushing to GitHub
###############################################################################
set -e

ACCOUNT_ID="603196661038"
REGION="ap-southeast-1"
ROLE_NAME="prod-github-ci-role"
GITHUB_REPO="sriram10412/Banking_App_Flask"

echo "======================================"
echo " Banking App Bootstrap (GitHub)"
echo " Account : ${ACCOUNT_ID}"
echo " Region  : ${REGION}"
echo "======================================"

# ── S3 state bucket ───────────────────────────────────────────────────────────
echo ""
echo "[1/5] S3 state bucket..."
aws s3api create-bucket \
  --bucket banking-app-tfstate \
  --region ${REGION} \
  --create-bucket-configuration LocationConstraint=${REGION} 2>/dev/null \
  && echo "  Created" || echo "  Already exists"

aws s3api put-bucket-versioning \
  --bucket banking-app-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket banking-app-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# ── DynamoDB lock table ───────────────────────────────────────────────────────
echo ""
echo "[2/5] DynamoDB lock table..."
aws dynamodb create-table \
  --table-name banking-app-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ${REGION} 2>/dev/null \
  && echo "  Created" || echo "  Already exists"

# ── GitHub OIDC Provider ──────────────────────────────────────────────────────
echo ""
echo "[3/5] GitHub OIDC provider..."
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 2>/dev/null \
  && echo "  Created" || echo "  Already exists"

# ── GitHub CI IAM Role ────────────────────────────────────────────────────────
echo ""
echo "[4/5] GitHub CI IAM role..."

cat > /tmp/trust-policy.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
TRUST

aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file:///tmp/trust-policy.json 2>/dev/null \
  && echo "  Role created" \
  || (aws iam update-assume-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-document file:///tmp/trust-policy.json \
      && echo "  Trust policy updated")

# Detach old policies
for POLICY_ARN in $(aws iam list-attached-role-policies \
  --role-name ${ROLE_NAME} \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text 2>/dev/null); do
  if [ "$POLICY_ARN" != "arn:aws:iam::aws:policy/AdministratorAccess" ]; then
    aws iam detach-role-policy \
      --role-name ${ROLE_NAME} \
      --policy-arn ${POLICY_ARN} 2>/dev/null || true
  fi
done

# Attach AdministratorAccess
aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>/dev/null \
  && echo "  AdministratorAccess attached" || echo "  Already attached"

# Set max session duration
aws iam update-role \
  --role-name ${ROLE_NAME} \
  --max-session-duration 7200

# ── Print outputs ─────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Done!"
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)
echo ""
echo "======================================"
echo " Set these in GitHub Secrets:"
echo " (Settings -> Secrets and variables -> Actions)"
echo "======================================"
echo ""
echo "  AWS_ROLE_ARN           = ${ROLE_ARN}"
echo "  AWS_ACCOUNT_ID         = ${ACCOUNT_ID}"
echo "  AWS_DEFAULT_REGION     = ${REGION}"
echo "  AWS_ACCESS_KEY_ID      = <your IAM user access key>"
echo "  AWS_SECRET_ACCESS_KEY  = <your IAM user secret key>"
echo "  ECS_CLUSTER_NAME       = prod-banking-cluster"
echo "  ECS_SERVICE_NAME       = prod-banking-service"
echo "  TF_VAR_DB_PASSWORD     = <your DB password>"
echo ""
echo " Then push to GitHub main branch to trigger pipeline!"
echo ""