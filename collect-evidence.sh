#!/bin/bash
# Usage: ./collect-evidence.sh <bucket-name> <ec2-address> <lambda-address>

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_URL="${2%/}"
LAMBDA_URL="${3%/}"
[[ "$EC2_URL" =~ ^https?:// ]] || EC2_URL="http://$EC2_URL"
[[ "$LAMBDA_URL" =~ ^https?:// ]] || LAMBDA_URL="https://$LAMBDA_URL"

ROLL="23l-3035"
EC2_ROLE="cv-ec2-role-$ROLL"
LAMBDA_ROLE="cv-lambda-role-$ROLL"
FUNCTION="cv-func-$ROLL"
INSTANCE_NAME="cv-ec2-$ROLL"
LOG_GROUP="/aws/lambda/$FUNCTION"
OUT="evidence.txt"

run() {
  echo "\$ $*"
  if ! "$@" 2>&1; then
    echo "!! command failed: $*"
  fi
  echo
}

section() {
  echo "== $1 =="
}

probe() {
  local label="$1" url="$2"
  printf '%-22s ' "$label"
  if ! curl -s -o /dev/null --max-time 15 -w '%{http_code} %{content_type} %{url_effective}\n' "$url"; then
    echo "!! request failed: $url"
  fi
}

REGION=$(aws s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text 2>/dev/null)
[ -z "$REGION" ] || [ "$REGION" = "None" ] && REGION="us-east-1"

{
  echo "Evidence collected $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "bucket=$BUCKET ec2=$EC2_URL lambda=$LAMBDA_URL region=$REGION"
  echo

  section caller
  run aws sts get-caller-identity

  section public-access
  run aws s3api get-public-access-block --bucket "$BUCKET"

  section versioning
  run aws s3api get-bucket-versioning --bucket "$BUCKET"

  section objects
  run aws s3 ls "s3://$BUCKET/site/" --recursive

  section ec2-policy
  POLICY=$(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames[0]' --output text 2>/dev/null)
  run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$POLICY"
  run aws iam list-attached-role-policies --role-name "$EC2_ROLE"

  section lambda-policy
  run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE"
  POLICY=$(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames[0]' --output text 2>/dev/null)
  run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$POLICY"

  section security-group
  SG_IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text 2>/dev/null)
  run aws ec2 describe-security-groups --region "$REGION" --group-ids $SG_IDS \
    --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Inbound:IpPermissions}'

  section instance
  run aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,PublicIp:PublicIpAddress,HttpTokens:MetadataOptions.HttpTokens,InstanceProfile:IamInstanceProfile.Arn,Tags:Tags}'

  section endpoints
  echo "label                  status content-type url"
  probe "ec2 /" "$EC2_URL/"
  probe "ec2 /style.css" "$EC2_URL/style.css"
  probe "ec2 /cv.pdf" "$EC2_URL/cv.pdf"
  probe "lambda /" "$LAMBDA_URL/"
  probe "lambda /style.css" "$LAMBDA_URL/style.css"
  probe "lambda /cv.pdf" "$LAMBDA_URL/cv.pdf"
  probe "lambda /anything" "$LAMBDA_URL/anything"
  probe "s3 direct index.html" "https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"
  echo

  section lambda-logs
  run aws logs tail "$LOG_GROUP" --region "$REGION" --since 1h --format short --filter-pattern '{ $.path = * }'

  section log-retention
  run aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "$LOG_GROUP" \
    --query 'logGroups[].{name:logGroupName,retentionInDays:retentionInDays}'
} > "$OUT"

echo DONE
