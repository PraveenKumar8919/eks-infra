# Destroy EKS Stack (Keep VPC)

Tears down all paid infrastructure — EKS cluster, NAT gateway, node groups, IAM roles, ACM cert, S3 bucket. Immediately recreates the VPC afterwards so it stays available for the next session.

## Pre-flight checks

1. Confirm working directory is `C:\joindevops-scripts\eks-infra\`
2. List what is currently running:
   ```bash
   aws eks list-clusters --region us-east-1
   aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].NatGatewayId" --output text --region us-east-1
   ```
3. Warn user: Route 53 records and ACM cert will be deleted. Grafana/Prometheus/Loki URLs will stop working.
4. Ask for confirmation before proceeding.

## Step 1 — Delete ALBs created by the ALB controller (REQUIRED first)

The ALB controller creates ALBs outside of Terraform (via Kubernetes Ingress objects). If these are not deleted before `terraform destroy`, the subnets will fail with `DependencyViolation` and the destroy will hang for hours.

```bash
# Delete all Kubernetes ingresses (triggers ALB controller to remove ALBs)
kubectl delete ingress --all -A

# Wait for ALBs to be fully removed
until [ $(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text) -eq 0 ]; do
  echo "Waiting for ALBs to delete..."; sleep 10
done
echo "ALBs deleted — safe to proceed"
```

If `kubectl` is unavailable (kubeconfig expired), delete ALBs and security groups directly:
```bash
# List and delete ALBs
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output table
aws elbv2 delete-load-balancer --load-balancer-arn <arn>

# Also delete leftover k8s security groups (they block VPC deletion too)
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'SecurityGroups[?starts_with(GroupName, `k8s-`)].[GroupId,GroupName]' --output table
aws ec2 delete-security-group --group-id <sg-id>
```

## Step 2 — Destroy everything

```bash
terraform destroy \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -var="create_nat_gateway=true"
```

This takes ~15 minutes. Destroys EKS, node groups, NAT gateway, IAM roles, ACM cert, S3 bucket, VPC.

Monitor progress — if node group deletion gets stuck:
```bash
# Check node group status
aws eks list-nodegroups --cluster-name eks-test-cluster --region us-east-1

# If stuck for more than 10 minutes, check instances and terminate manually
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=eks-test-cluster" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" --output text --region us-east-1

# Terminate if stuck
aws ec2 terminate-instances --instance-ids <instance-ids> --region us-east-1
```

If Terraform state lock error appears after a failed/cancelled run:
```bash
terraform force-unlock -force <lock-id>
```

## Step 3 — Recreate VPC (free, ~2 minutes)

```bash
terraform apply \
  -target=module.vpc \
  -var="loki_s3_bucket=ppattirik-loki-logs"
```

Creates: VPC, 3 public subnets, 3 private subnets, Internet Gateway, route tables. No NAT gateway.

## Step 4 — Verify

```bash
# VPC should be back
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-test-cluster-vpc" \
  --query "Vpcs[*].[VpcId,State]" --output table --region us-east-1

# EKS should be gone
aws eks list-clusters --region us-east-1

# No NAT gateways
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available,pending" \
  --query "NatGateways[*].NatGatewayId" --output text --region us-east-1
```

## Step 5 — Update CLAUDE.md state table

Update the infrastructure state table in `.claude/CLAUDE.md` to reflect:
- VPC: Running (new VPC ID from Step 2 output)
- NAT Gateway: Not created
- EKS cluster: Not created
- Spot nodes: Not created
