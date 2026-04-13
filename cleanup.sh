#!/bin/bash
set -e
REGION="ap-southeast-1"
ACCOUNT_ID="603196661038"

echo "================================================"
echo " STEP 1: CLEANUP ALL EXISTING AWS RESOURCES"
echo "================================================"

# ── ECS ───────────────────────────────────────────────────────────────────────
echo "Cleaning ECS..."
aws ecs update-service --cluster prod-banking-cluster --service prod-banking-service --desired-count 0 --region ${REGION} 2>/dev/null || true
aws ecs delete-service --cluster prod-banking-cluster --service prod-banking-service --force --region ${REGION} 2>/dev/null || true
aws ecs delete-cluster --cluster prod-banking-cluster --region ${REGION} 2>/dev/null || true

# ── ALB ───────────────────────────────────────────────────────────────────────
echo "Cleaning ALB..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names prod-banking-alb --region ${REGION} --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
if [ ! -z "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 modify-load-balancer-attributes --load-balancer-arn ${ALB_ARN} --attributes Key=deletion_protection.enabled,Value=false --region ${REGION} 2>/dev/null || true
  # Delete listeners first
  for LISTENER in $(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} --region ${REGION} --query 'Listeners[*].ListenerArn' --output text 2>/dev/null); do
    aws elbv2 delete-listener --listener-arn ${LISTENER} --region ${REGION} 2>/dev/null || true
  done
  aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} --region ${REGION} 2>/dev/null || true
  echo "Waiting for ALB deletion..."
  sleep 30
fi

# ── Target Groups ─────────────────────────────────────────────────────────────
echo "Cleaning target groups..."
for TG in $(aws elbv2 describe-target-groups --region ${REGION} --query 'TargetGroups[?contains(TargetGroupName,`banking`)].TargetGroupArn' --output text 2>/dev/null); do
  aws elbv2 delete-target-group --target-group-arn ${TG} --region ${REGION} 2>/dev/null || true
done

# ── RDS ───────────────────────────────────────────────────────────────────────
echo "Cleaning RDS..."
aws rds modify-db-instance --db-instance-identifier prod-banking-db --no-deletion-protection --region ${REGION} 2>/dev/null || true
aws rds delete-db-instance --db-instance-identifier prod-banking-db --skip-final-snapshot --region ${REGION} 2>/dev/null || true
echo "Waiting for RDS deletion (this takes ~10 mins)..."
aws rds wait db-instance-deleted --db-instance-identifier prod-banking-db --region ${REGION} 2>/dev/null || true

aws rds delete-db-subnet-group --db-subnet-group-name prod-banking-db-subnet-group --region ${REGION} 2>/dev/null || true
aws rds delete-db-parameter-group --db-parameter-group-name prod-banking-pg14 --region ${REGION} 2>/dev/null || true
aws rds delete-db-parameter-group --db-parameter-group-name prod-banking-pg15 --region ${REGION} 2>/dev/null || true

# ── ECR ───────────────────────────────────────────────────────────────────────
echo "Cleaning ECR..."
aws ecr delete-repository --repository-name prod-banking-app --force --region ${REGION} 2>/dev/null || true

# ── Secrets Manager ───────────────────────────────────────────────────────────
echo "Cleaning Secrets Manager..."
aws secretsmanager delete-secret --secret-id prod/banking-app/db-credentials --force-delete-without-recovery --region ${REGION} 2>/dev/null || true

# ── KMS ───────────────────────────────────────────────────────────────────────
echo "Cleaning KMS..."
aws kms delete-alias --alias-name alias/prod-rds --region ${REGION} 2>/dev/null || true
aws kms delete-alias --alias-name alias/prod-ecs --region ${REGION} 2>/dev/null || true

# ── CloudWatch Logs ───────────────────────────────────────────────────────────
echo "Cleaning CloudWatch logs..."
aws logs delete-log-group --log-group-name /aws/vpc/prod-banking-flow-logs --region ${REGION} 2>/dev/null || true
aws logs delete-log-group --log-group-name /ecs/prod/banking-app --region ${REGION} 2>/dev/null || true

# ── SNS ───────────────────────────────────────────────────────────────────────
echo "Cleaning SNS..."
SNS_ARN=$(aws sns list-topics --region ${REGION} --query "Topics[?contains(TopicArn,'banking')].TopicArn" --output text 2>/dev/null || echo "")
[ ! -z "$SNS_ARN" ] && aws sns delete-topic --topic-arn ${SNS_ARN} --region ${REGION} 2>/dev/null || true

# ── IAM Policies ──────────────────────────────────────────────────────────────
echo "Cleaning IAM policies..."
for POLICY in prod-gitlab-ci-ecr-policy prod-gitlab-ci-ecs-policy prod-gitlab-ci-tf-state-policy prod-gitlab-ci-tf-infra-policy prod-ecs-secrets-policy prod-ecs-task-app-policy; do
  POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${POLICY}'].Arn" --output text 2>/dev/null || echo "")
  if [ ! -z "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
    # Detach from all roles first
    for ROLE in $(aws iam list-entities-for-policy --policy-arn ${POLICY_ARN} --query 'PolicyRoles[].RoleName' --output text 2>/dev/null); do
      aws iam detach-role-policy --role-name ${ROLE} --policy-arn ${POLICY_ARN} 2>/dev/null || true
    done
    aws iam delete-policy --policy-arn ${POLICY_ARN} 2>/dev/null || true
  fi
done

# ── IAM Roles ─────────────────────────────────────────────────────────────────
echo "Cleaning IAM roles..."
for ROLE in prod-gitlab-ci-role prod-ecs-task-execution-role prod-ecs-task-role prod-rds-monitoring-role prod-vpc-flow-logs-role; do
  # Detach all managed policies
  for POLICY_ARN in $(aws iam list-attached-role-policies --role-name ${ROLE} --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name ${ROLE} --policy-arn ${POLICY_ARN} 2>/dev/null || true
  done
  # Delete inline policies
  for POLICY_NAME in $(aws iam list-role-policies --role-name ${ROLE} --query 'PolicyNames[]' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name ${ROLE} --policy-name ${POLICY_NAME} 2>/dev/null || true
  done
  aws iam delete-role --role-name ${ROLE} 2>/dev/null || true
  echo "  Deleted role: ${ROLE}"
done

# ── Security Groups ───────────────────────────────────────────────────────────
echo "Cleaning security groups..."
for SG_NAME in prod-alb-sg prod-ecs-sg prod-rds-sg; do
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" --region ${REGION} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
  if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id ${SG_ID} --region ${REGION} 2>/dev/null || true
    echo "  Deleted SG: ${SG_NAME}"
  fi
done

# ── Release unused EIPs ───────────────────────────────────────────────────────
echo "Releasing unassociated EIPs..."
for ALLOC in $(aws ec2 describe-addresses --region ${REGION} --query 'Addresses[?AssociationId==null].AllocationId' --output text 2>/dev/null); do
  aws ec2 release-address --allocation-id ${ALLOC} --region ${REGION} 2>/dev/null || true
  echo "  Released EIP: ${ALLOC}"
done

# ── Delete unused VPCs (keep default) ────────────────────────────────────────
echo "Cleaning unused VPCs..."
for VPC_ID in $(aws ec2 describe-vpcs --region ${REGION} --query 'Vpcs[?IsDefault==`false`].VpcId' --output text 2>/dev/null); do
  echo "  Deleting VPC: ${VPC_ID}"

  # Delete subnets
  for SUBNET in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --region ${REGION} --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
    aws ec2 delete-subnet --subnet-id ${SUBNET} --region ${REGION} 2>/dev/null || true
  done

  # Delete route tables (non-main)
  for RT in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" --region ${REGION} --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' --output text 2>/dev/null); do
    aws ec2 delete-route-table --route-table-id ${RT} --region ${REGION} 2>/dev/null || true
  done

  # Detach and delete IGW
  for IGW in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --region ${REGION} --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null); do
    aws ec2 detach-internet-gateway --internet-gateway-id ${IGW} --vpc-id ${VPC_ID} --region ${REGION} 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id ${IGW} --region ${REGION} 2>/dev/null || true
  done

  # Delete NAT Gateways
  for NAT in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" --region ${REGION} --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null); do
    aws ec2 delete-nat-gateway --nat-gateway-id ${NAT} --region ${REGION} 2>/dev/null || true
  done

  aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${REGION} 2>/dev/null || true
done

# ── S3 ALB Logs bucket ────────────────────────────────────────────────────────
echo "Cleaning S3 bucket..."
aws s3 rm s3://prod-banking-alb-logs-${ACCOUNT_ID} --recursive --region ${REGION} 2>/dev/null || true
aws s3api delete-bucket --bucket prod-banking-alb-logs-${ACCOUNT_ID} --region ${REGION} 2>/dev/null || true

echo ""
echo "================================================"
echo " STEP 2: CLEAR TERRAFORM STATE"
echo "================================================"
terraform state list 2>/dev/null | xargs -I {} terraform state rm {} 2>/dev/null || true
echo "Terraform state cleared"

echo ""
echo "================================================"
echo " STEP 3: IMPORT OIDC PROVIDER (cannot delete)"
echo "================================================"
terraform import module.iam.aws_iam_openid_connect_provider.gitlab \
  arn:aws:iam::${ACCOUNT_ID}:oidc-provider/gitlab.com

echo ""
echo "================================================"
echo " CLEANUP COMPLETE - Ready for fresh apply"
echo "================================================"
echo ""
echo "Now run:"
echo "  terraform apply -var-file=environments/prod/terraform.tfvars"
