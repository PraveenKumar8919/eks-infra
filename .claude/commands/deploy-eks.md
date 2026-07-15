# Deploy EKS Stack

Deploy the full EKS observability stack end-to-end. This skill runs all steps in order, verifies each one before proceeding, and reports status at the end.

## Pre-flight checks

Before doing anything:
1. Confirm working directory is `C:\joindevops-scripts\eks-infra\`
2. Confirm VPC exists: `aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-test-cluster-vpc" --query "Vpcs[*].VpcId" --output text --region us-east-1`
3. Confirm no EKS cluster already running: `aws eks list-clusters --region us-east-1`
4. Warn the user of estimated cost: ~$0.25/hr (~$6/day) while cluster is running

## Step 1 — Terraform init

```bash
terraform init \
  -backend-config="bucket=ppattirik-remote-bucket" \
  -backend-config="key=eks-infra/state.tfstate" \
  -backend-config="region=us-east-1"
```

## Step 2 — Terraform plan (show user what will be created)

```bash
terraform plan \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -var="create_nat_gateway=true"
```

Show the user the plan summary and ask for confirmation before applying.

## Step 3 — Terraform apply

```bash
terraform apply \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -var="create_nat_gateway=true"
```

This takes ~15 minutes. Creates:
- NAT Gateway (private subnet internet access)
- EKS cluster `eks-test-cluster` with Spot node group (2x t3.xlarge/m5.xlarge)
- EBS CSI driver addon
- IAM roles (IRSA) for Loki, ALB controller, ExternalDNS, EBS CSI
- ACM wildcard cert `*.devopswithpraveen.online` with Route 53 DNS validation
- S3 bucket for Loki log storage

## Step 4 — Update kubeconfig

```bash
aws eks update-kubeconfig --name eks-test-cluster --region us-east-1
kubectl get nodes
```

Verify nodes are in `Ready` state before proceeding.

## Step 5 — Deploy observability + apps via Ansible

Instruct the user to go to:
**GitHub → eks-ansible → Actions → EKS Configuration (Helm via Ansible) → Run workflow**

This deploys (in order):
1. AWS Load Balancer Controller
2. ExternalDNS (auto Route 53 records)
3. Loki (log storage → S3)
4. kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
5. Grafana Alloy (DaemonSet — collects logs + metrics from all nodes)
6. Roboshop (10-microservice e-commerce app)

## Step 6 — Verify access

After the Ansible workflow completes (~10 minutes), verify:

```bash
kubectl get ingress -A
kubectl get pods -n grafana
kubectl get pods -n loki-live
kubectl get pods -n monitoring
kubectl get pods -n roboshop
```

Access URLs:
- https://grafana.devopswithpraveen.online (admin / DevOps@2025)
- https://prometheus.devopswithpraveen.online
- https://loki.devopswithpraveen.online

## Step 7 — Report to user

Print a summary:
- Cluster name and endpoint
- All access URLs
- Current cost per hour
- Reminder to run `/destroy-eks` when done practicing
