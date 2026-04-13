#!/bin/bash
REGION="ap-southeast-1"
ACCOUNT_ID="603196661038"

echo "=== Deleting GitLab created resources ==="

# RDS subnet group
echo "[1] Deleting RDS subnet group..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name prod-banking-db-subnet-group \
  --region ${REGION} 2>/dev/null || echo "Not found"

# RDS parameter group
echo "[2] Deleting RDS parameter group..."
aws rds delete-db-parameter-group \
  --db-parameter-group-name prod-banking-pg14 \
  --region ${REGION} 2>/dev/null || echo "Not found"

# RDS monitoring role
echo "[3] Deleting RDS monitoring role..."
aws iam detach-role-policy \
  --role-name prod-rds-monitoring-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole \
  --region ${REGION} 2>/dev/null || true
aws iam delete-role \
  --role-name prod-rds-monitoring-role 2>/dev/null || echo "Not found"

# Secrets Manager secret
echo "[4] Deleting secret..."
aws secretsmanager delete-secret \
  --secret-id prod/banking-app/db-credentials \
  --force-delete-without-recovery \
  --region ${REGION} 2>/dev/null || echo "Not found"

# VPC flow logs log group
echo "[5] Deleting VPC flow logs log group..."
aws logs delete-log-group \
  --log-group-name /aws/vpc/prod-banking-flow-logs \
  --region ${REGION} 2>/dev/null || echo "Not found"

# VPC flow logs IAM role
echo "[6] Deleting VPC flow logs role..."
aws iam delete-role-policy \
  --role-name prod-vpc-flow-logs-role \
  --policy-name prod-vpc-flow-logs-policy 2>/dev/null || true
aws iam delete-role \
  --role-name prod-vpc-flow-logs-role 2>/dev/null || echo "Not found"

# ECS log group
echo "[7] Deleting ECS log group..."
aws logs delete-log-group \
  --log-group-name /ecs/prod/banking-app \
  --region ${REGION} 2>/dev/null || echo "Not found"

# ECS task execution role
echo "[8] Deleting ECS task execution role..."
for POLICY in $(aws iam list-attached-role-policies \
  --role-name prod-ecs-task-execution-role \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text 2>/dev/null); do
  aws iam detach-role-policy \
    --role-name prod-ecs-task-execution-role \
    --policy-arn ${POLICY} 2>/dev/null || true
done
for POLICY in $(aws iam list-role-policies \
  --role-name prod-ecs-task-execution-role \
  --query 'PolicyNames[]' \
  --output text 2>/dev/null); do
  aws iam delete-role-policy \
    --role-name prod-ecs-task-execution-role \
    --policy-name ${POLICY} 2>/dev/null || true
done
aws iam delete-role \
  --role-name prod-ecs-task-execution-role 2>/dev/null || echo "Not found"

# ECS task role
echo "[9] Deleting ECS task role..."
for POLICY in $(aws iam list-attached-role-policies \
  --role-name prod-ecs-task-role \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text 2>/dev/null); do
  aws iam detach-role-policy \
    --role-name prod-ecs-task-role \
    --policy-arn ${POLICY} 2>/dev/null || true
done
for POLICY in $(aws iam list-role-policies \
  --role-name prod-ecs-task-role \
  --query 'PolicyNames[]' \
  --output text 2>/dev/null); do
  aws iam delete-role-policy \
    --role-name prod-ecs-task-role \
    --policy-name ${POLICY} 2>/dev/null || true
done
aws iam delete-role \
  --role-name prod-ecs-task-role 2>/dev/null || echo "Not found"

# IAM policies
echo "[10] Deleting IAM policies..."
for POLICY in prod-ecs-secrets-policy prod-ecs-task-app-policy; do
  POLICY_ARN=$(aws iam list-policies \
    --scope Local \
    --query "Policies[?PolicyName=='${POLICY}'].Arn" \
    --output text 2>/dev/null || echo "")
  if [ ! -z "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
    aws iam delete-policy --policy-arn ${POLICY_ARN} 2>/dev/null || true
    echo "  Deleted: ${POLICY}"
  fi
done

# ECR repository
echo "[11] Deleting ECR repository..."
aws ecr delete-repository \
  --repository-name prod-banking-app \
  --force \
  --region ${REGION} 2>/dev/null || echo "Not found"

# ALB
echo "[12] Deleting ALB..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names prod-banking-alb \
  --region ${REGION} \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || echo "")
if [ ! -z "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn ${ALB_ARN} \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region ${REGION} 2>/dev/null || true
  # Delete listeners first
  for LISTENER in $(aws elbv2 describe-listeners \
    --load-balancer-arn ${ALB_ARN} \
    --region ${REGION} \
    --query 'Listeners[*].ListenerArn' \
    --output text 2>/dev/null); do
    aws elbv2 delete-listener \
      --listener-arn ${LISTENER} \
      --region ${REGION} 2>/dev/null || true
  done
  aws elbv2 delete-load-balancer \
    --load-balancer-arn ${ALB_ARN} \
    --region ${REGION} 2>/dev/null || true
  echo "  Waiting for ALB deletion..."
  sleep 30
fi

# Target groups
echo "[13] Deleting target groups..."
for TG in $(aws elbv2 describe-target-groups \
  --region ${REGION} \
  --query 'TargetGroups[?contains(TargetGroupName,`banking`)].TargetGroupArn' \
  --output text 2>/dev/null); do
  aws elbv2 delete-target-group \
    --target-group-arn ${TG} \
    --region ${REGION} 2>/dev/null || true
done

# Security groups
echo "[14] Deleting security groups..."
for SG_NAME in prod-alb-sg prod-ecs-sg prod-rds-sg; do
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --region ${REGION} \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")
  if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group \
      --group-id ${SG_ID} \
      --region ${REGION} 2>/dev/null || true
    echo "  Deleted: ${SG_NAME}"
  fi
done

# S3 ALB logs bucket
echo "[15] Deleting ALB logs S3 bucket..."
aws s3 rm s3://prod-banking-alb-logs-${ACCOUNT_ID} --recursive \
  --region ${REGION} 2>/dev/null || true
aws s3api delete-bucket \
  --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
  --region ${REGION} 2>/dev/null || echo "Not found"

# KMS alias
echo "[16] Deleting KMS alias..."
aws kms delete-alias \
  --alias-name alias/prod-rds \
  --region ${REGION} 2>/dev/null || echo "Not found"
aws kms delete-alias \
  --alias-name alias/prod-ecs \
  --region ${REGION} 2>/dev/null || echo "Not found"

# CloudWatch alarms
echo "[17] Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms \
  --alarm-names \
    prod-banking-ecs-cpu-high \
    prod-banking-alb-5xx \
    prod-banking-rds-cpu-high \
  --region ${REGION} 2>/dev/null || echo "Not found"

# Also clear the old GitLab Terraform state
echo "[18] Clearing old Terraform state..."
aws dynamodb delete-item \
  --table-name banking-app-tfstate-lock \
  --key '{"LockID":{"S":"banking-app-tfstate/prod/terraform.tfstate-md5"}}' \
  --region ${REGION} 2>/dev/null || true
aws dynamodb delete-item \
  --table-name banking-app-tfstate-lock \
  --key '{"LockID":{"S":"banking-app-tfstate/prod/terraform.tfstate"}}' \
  --region ${REGION} 2>/dev/null || true

# Delete the old state file from S3
aws s3 rm s3://banking-app-tfstate/prod/terraform.tfstate \
  --region ${REGION} 2>/dev/null || true

echo ""
echo "================================================"
echo " All GitLab resources deleted!"
echo " GitHub pipeline will now create fresh resources"
echo "================================================"
