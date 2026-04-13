REGION="ap-southeast-1"
ACCOUNT_ID="603196661038"

# Delete S3 ALB logs bucket - empty it first including versions
echo "Deleting S3 bucket..."
aws s3 rm s3://prod-banking-alb-logs-${ACCOUNT_ID} --recursive --region ${REGION} 2>/dev/null || true

VERSIONS=$(aws s3api list-object-versions \
  --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json 2>/dev/null || echo '{"Objects":[]}')
if [ "$VERSIONS" != '{"Objects":[]}' ] && [ "$VERSIONS" != 'null' ]; then
  aws s3api delete-objects \
    --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
    --delete "${VERSIONS}" --region ${REGION} 2>/dev/null || true
fi

MARKERS=$(aws s3api list-object-versions \
  --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json 2>/dev/null || echo '{"Objects":[]}')
if [ "$MARKERS" != '{"Objects":[]}' ] && [ "$MARKERS" != 'null' ]; then
  aws s3api delete-objects \
    --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
    --delete "${MARKERS}" --region ${REGION} 2>/dev/null || true
fi

aws s3api delete-bucket \
  --bucket prod-banking-alb-logs-${ACCOUNT_ID} \
  --region ${REGION} 2>/dev/null && echo "S3 bucket deleted" || echo "S3 bucket not found"

# Delete RDS subnet group
echo "Deleting RDS subnet group..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name prod-banking-db-subnet-group \
  --region ${REGION} 2>/dev/null && echo "Subnet group deleted" || echo "Not found"

# Delete RDS parameter group
echo "Deleting RDS parameter group..."
aws rds delete-db-parameter-group \
  --db-parameter-group-name prod-banking-pg14 \
  --region ${REGION} 2>/dev/null && echo "Parameter group deleted" || echo "Not found"

echo ""
echo "Done - now retrigger the pipeline"
