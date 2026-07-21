# Deploy EKS Stack — Full End-to-End Agent

Fully autonomous deployment: provisions EKS cluster via Terraform, waits for nodes to be Ready, triggers the Ansible GitHub Actions workflow, monitors it, and reports all access URLs. No manual steps required.

---

## Pre-flight checks

Run these first. Stop and report to the user if anything is wrong.

```bash
# 1. Confirm correct working directory
pwd  # must be C:\joindevops-scripts\eks-infra

# 2. Check if cluster already exists (skip Terraform if so)
aws eks list-clusters --region us-east-1 --output text

# 3. Check VPC exists
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=eks-test-cluster-vpc" \
  --query "Vpcs[*].[VpcId,State]" --output table --region us-east-1

# 4. Check for stale state lock before doing anything
terraform force-unlock -force <lock-id>  # only if a lock error appears later
```

Warn the user of estimated cost before proceeding: **~$0.25/hr (~$6/day)** while cluster is running.

---

## Step 1 — Terraform apply (VPC + EKS)

If VPC already exists from a previous session, skip the `-target=module.vpc` step and go straight to the full apply.

**If VPC does not exist yet:**
```bash
terraform apply -target=module.vpc \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -auto-approve
```

**Full EKS stack (~25 min, run in background):**
```bash
terraform apply \
  -var="loki_s3_bucket=ppattirik-loki-logs" \
  -var="create_nat_gateway=true" \
  -auto-approve
```

Run this in the background and tail the output. If a state lock error appears:
```bash
terraform force-unlock -force <lock-id>
# then re-run the apply
```

Known behaviour: node group takes ~15 min to become healthy. `before_compute = true` is set on vpc-cni/kube-proxy/coredns in `main.tf` — nodes will come up Ready without manual intervention.

---

## Step 2 — Update kubeconfig and verify nodes

```bash
aws eks update-kubeconfig --name eks-test-cluster --region us-east-1
kubectl get nodes
```

**Do not proceed to Step 3 until both nodes show `Ready`.** If nodes are `NotReady` after 20 minutes:
```bash
kubectl get pods -n kube-system          # check vpc-cni / coredns
kubectl describe node <node-name>        # look at conditions
```

---

## Step 3 — Trigger Ansible workflow

Trigger the workflow via CLI (no browser needed):
```bash
gh workflow run config.yml --repo PraveenKumar8919/eks-ansible --ref main
```

Wait 5 seconds then get the run ID:
```bash
gh run list --repo PraveenKumar8919/eks-ansible --limit 1 --workflow config.yml
```

Monitor it in the background:
```bash
gh run watch <run-id> --repo PraveenKumar8919/eks-ansible
```

The workflow (~5 min) deploys in order:
1. AWS Load Balancer Controller (kube-system)
2. ExternalDNS (kube-system — creates Route 53 records)
3. Loki (loki-live — log storage → S3)
4. kube-prometheus-stack (grafana — Prometheus + Grafana + Alertmanager)
5. Grafana Alloy (monitoring — log + metrics DaemonSet)
6. Roboshop (roboshop — 10 microservices)

**Known failure modes and fixes:**

| Error | Fix |
|-------|-----|
| `community.general.yaml callback removed` | Already fixed in ansible.cfg |
| `cluster_name is undefined` | Already fixed — hosts file exists at repo root |
| Loki PVC unbound | Already fixed — pre_task sets gp2 as default StorageClass |
| `vault_grafana_admin_password undefined` | Already fixed — using env vars not vault |
| `SetRulePriorities AccessDenied` | Already fixed in alb-controller-policy.json |
| Loki StatefulSet timeout | Already fixed — chunksCache disabled, timeout 10m |

If the workflow fails, check logs:
```bash
gh run view --log-failed --repo PraveenKumar8919/eks-ansible
```
Fix the issue, push to main, then trigger a **fresh** run (never re-run old jobs — they use the original commit):
```bash
gh workflow run config.yml --repo PraveenKumar8919/eks-ansible --ref main
```

---

## Step 4 — Verify everything is running

```bash
# Nodes
kubectl get nodes

# All pods (look for Running, no CrashLoopBackOff)
kubectl get pods -A | grep -v Completed

# Ingresses have ALB addresses
kubectl get ingress -A
```

If Grafana/Prometheus ingresses have no ALB address after 2 min:
```bash
kubectl describe ingress kube-prometheus-stack-grafana -n grafana | tail -20
# Look for AccessDenied errors → check ALB controller IAM policy
# Then restart: kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

## Step 5 — Report to user

Print a clean summary:

```
=== EKS Cluster Ready ===
Cluster:    eks-test-cluster (us-east-1)
Nodes:      2x Spot (Ready)
Cost:       ~$0.25/hr — remember to destroy when done

=== Access URLs ===
Grafana:    https://grafana.devopswithpraveen.online
            Login: admin / <get from: kubectl get secret -n grafana kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d>
Prometheus: https://prometheus.devopswithpraveen.online
Loki:       https://loki.devopswithpraveen.online

=== Roboshop ===
kubectl get ingress -n roboshop

=== When done practicing ===
Run: /destroy-eks
```

Get the actual Grafana password:
```bash
kubectl get secret -n grafana kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```
