# EKS Infra — Agent Instructions

This repo provisions an EKS observability + roboshop learning cluster on AWS using Terraform.
Companion repo for Ansible/Helm deployments: https://github.com/PraveenKumar8919/eks-ansible

---

## Rules — follow these before doing anything

1. **GitHub Actions workflows never run `terraform apply`** — workflows run `terraform plan` only. Never add apply/destroy to any workflow.

2. **All applies and destroys run locally** from `C:\joindevops-scripts\eks-infra\`.

3. **VPC is permanent** — `vpc-06606998911fb7379` (10.0.0.0/16) must never be destroyed. If a full `terraform destroy` is needed, immediately recreate the VPC with `terraform apply -target=module.vpc` afterwards.

4. **NAT Gateway is paid — only create with EKS** — never create the NAT gateway in isolation. It must be created at the same time as the EKS cluster using `-var="create_nat_gateway=true"`. Default is `false`.

5. **Free resources** (VPC, subnets, IGW, route tables, ACM cert) can be created anytime at no cost.

6. **Paid resources** (NAT Gateway ~$0.045/hr, EKS ~$0.10/hr, Spot nodes ~$0.10/hr) only exist when actively practicing. Always destroy when done.

---

## Current infrastructure state

| Resource | State | Cost |
|----------|-------|------|
| VPC `vpc-0f4be68f7bc10b8cf` | **Running** | Free |
| 3 public subnets | **Running** | Free |
| 3 private subnets | **Running** | Free |
| Internet Gateway | **Running** | Free |
| NAT Gateway | Not created | — |
| EKS cluster `eks-test-cluster` | Not created | — |
| Spot nodes | Not created | — |

**Update this table whenever infra state changes.**

## Known gotcha — EKS module v21 core add-ons

EKS module v21 does NOT auto-install vpc-cni, kube-proxy, or coredns.
They MUST be declared explicitly in the `addons` block in `main.tf`.
Without `vpc-cni`, nodes join but stay NotReady → `NodeCreationFailure`.
This is already fixed in `main.tf`.

---

## Terraform backend

```bash
terraform init \
  -backend-config="bucket=ppattirik-remote-bucket" \
  -backend-config="key=eks-infra/state.tfstate" \
  -backend-config="region=us-east-1"
```

## Key variables

| Variable | Value |
|----------|-------|
| `loki_s3_bucket` | `ppattirik-loki-logs` |
| `create_nat_gateway` | `true` with EKS, `false` for VPC-only |
| `cluster_name` | `eks-test-cluster` |
| `domain_name` | `devopswithpraveen.online` |
| AWS region | `us-east-1` |

---

## Agents available

Agents run autonomously end-to-end — spawn them when the user asks to deploy or destroy.

| Agent | File | Trigger phrases | What it does |
|-------|------|-----------------|--------------|
| `eks-deploy` | `.claude/agents/eks-deploy.md` | "spin up the cluster", "deploy EKS", "create infra" | Terraform apply → wait for nodes Ready → trigger Ansible workflow → monitor → verify → report URLs |
| `eks-destroy` | `.claude/agents/eks-destroy.md` | "destroy all infra", "tear down", "done practicing" | ALB/SG cleanup → terraform destroy → verify gone → recreate free VPC |

## Skills available (step-by-step guidance)

- `/deploy-eks` — guided deploy walkthrough
- `/destroy-eks` — guided destroy walkthrough

## Key files

| File | Purpose |
|------|---------|
| `main.tf` | EKS cluster, node group, add-ons |
| `cleanup.tf` | Destroy-time provisioner — auto-deletes ALBs + k8s SGs before VPC is removed |
| `destroy.sh` | Last-resort manual destroy script if cleanup.tf provisioner fails |
| `policies/alb-controller-policy.json` | ALB controller IAM policy (includes SetRulePriorities) |
