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

## Step 1 — Destroy everything

`cleanup.tf` contains a `null_resource` with a destroy-time provisioner that **automatically** deletes ALB-controller ALBs and security groups before the VPC is destroyed. No manual pre-steps needed.

```bash
terraform destroy \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -var="create_nat_gateway=true"
```

The provisioner in `cleanup.tf` will run first and handle:
- Deleting all Kubernetes ingresses (triggers ALB deletion)
- Waiting for ALBs to be fully removed
- Deleting leftover `k8s-*` security groups

## If Step 1 fails (destroy-time provisioner didn't run or errored)

Run `destroy.sh` as a last resort — it does all the cleanup manually then runs terraform destroy:

```bash
bash destroy.sh
```

What it handles:
- Deletes ingresses via kubectl (falls back to direct AWS CLI if kubectl unavailable)
- Waits for ALBs to delete
- Deletes `k8s-*` security groups
- Runs `terraform destroy`
- Recreates free VPC

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
