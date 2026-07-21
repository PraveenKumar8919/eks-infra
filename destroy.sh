#!/usr/bin/env bash
set -euo pipefail

LOKI_BUCKET="ppattirik-loki-logs"
REGION="us-east-1"

echo "=== Step 1: Delete Kubernetes ingresses (triggers ALB controller to remove ALBs) ==="
if kubectl cluster-info &>/dev/null; then
  kubectl delete ingress --all -A --ignore-not-found
  echo "Waiting for ALBs to be deleted..."
  until [ "$(aws elbv2 describe-load-balancers --region "$REGION" --query 'length(LoadBalancers)' --output text 2>/dev/null)" = "0" ]; do
    echo "  ALBs still deleting..."; sleep 10
  done
  echo "  ALBs gone."
else
  echo "  kubectl unavailable — checking for ALBs directly..."
  ALBS=$(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null)
  for arn in $ALBS; do
    echo "  Deleting ALB: $arn"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$REGION"
  done
  if [ -n "$ALBS" ]; then
    echo "  Waiting for ALBs to finish deleting..."
    until [ "$(aws elbv2 describe-load-balancers --region "$REGION" --query 'length(LoadBalancers)' --output text)" = "0" ]; do
      sleep 10
    done
  fi
  echo "  ALBs gone."
fi

echo ""
echo "=== Step 2: Delete leftover k8s security groups ==="
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?starts_with(GroupName, `k8s-`)].GroupId' \
    --output text --region "$REGION" 2>/dev/null)
  for sg in $SGS; do
    echo "  Deleting security group: $sg"
    aws ec2 delete-security-group --group-id "$sg" --region "$REGION"
  done
  [ -z "$SGS" ] && echo "  No k8s security groups found."
else
  echo "  Could not determine VPC ID — skipping security group cleanup."
fi

echo ""
echo "=== Step 3: Terraform destroy ==="
terraform destroy \
  -var="loki_s3_bucket=${LOKI_BUCKET}" \
  -var="create_nat_gateway=true" \
  -auto-approve

echo ""
echo "=== Step 4: Recreate free VPC ==="
terraform apply \
  -target=module.vpc \
  -var="loki_s3_bucket=${LOKI_BUCKET}" \
  -auto-approve

echo ""
echo "=== Done. All paid resources destroyed. VPC recreated. ==="
terraform output vpc_id
