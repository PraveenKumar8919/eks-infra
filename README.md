# eks-infra

Terraform code to provision an AWS EKS cluster and supporting infrastructure. This repo handles **pure AWS resources only** — no application deployments.

Application and Helm deployments live in [eks-ansible](https://github.com/PraveenKumar8919/eks-ansible).

---

## What this repo creates

```
AWS
├── EKS Cluster (Spot managed node group)   ← t3.xlarge/m5.xlarge Spot instances
├── ACM Certificate                          ← wildcard *.devopswithpraveen.online
├── ALB Controller IAM Role (IRSA)          ← lets ALB controller create load balancers
├── ExternalDNS IAM Role (IRSA)             ← lets ExternalDNS update Route 53 records
├── EBS CSI Driver IAM Role (IRSA)          ← lets EBS CSI driver create volumes
├── Loki IAM Role (IRSA)                    ← lets Loki write logs to S3
└── S3 Bucket                               ← Loki log storage
```

### Why Spot instances?
Spot instances cost 60–90% less than On-Demand. For a test/learning cluster this is ideal. The node group uses multiple instance types (`t3.xlarge`, `t3a.xlarge`, `m5.xlarge`, `m5a.xlarge`) so if one Spot pool runs out, AWS falls back to another.

### Why IRSA (IAM Roles for Service Accounts)?
Instead of putting AWS credentials inside a Kubernetes Secret, IRSA lets a pod assume an IAM role directly using Kubernetes identity. No credentials ever touch the cluster.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Terraform >= 1.10](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | AWS authentication |
| An S3 bucket for Terraform state | Remote state storage |
| A VPC with at least 2 public subnets in different AZs | EKS networking |
| `devopswithpraveen.online` managed in Route 53 | DNS for subdomain creation |

---

## Repository structure

```
eks-infra/
├── .github/
│   └── workflows/
│       ├── infra.yml              # Terraform plan + apply on push to main
│       └── security-scan.yml      # Trivy secret + IaC misconfiguration scan
├── policies/
│   └── alb-controller-policy.json # Official ALB controller IAM policy
├── main.tf                         # EKS cluster + Spot node group + EBS CSI addon
├── provider.tf                     # AWS provider + S3 backend (no hardcoded bucket)
├── variables.tf                    # Input variables
├── outputs.tf                      # Outputs consumed by eks-ansible via S3 state
├── iam.tf                          # IRSA role for Loki → S3
├── ebs-csi-iam.tf                  # IRSA role for EBS CSI driver
├── acm.tf                          # ACM wildcard cert + Route 53 DNS validation
├── alb-iam.tf                      # IRSA role for AWS Load Balancer Controller
├── externaldns-iam.tf              # IRSA role for ExternalDNS
├── s3.tf                           # S3 bucket for Loki log storage
├── terraform.tfvars.example        # Template — copy to terraform.tfvars for local use
└── .gitignore
```

---

## Local usage

**1. Clone the repo**
```bash
git clone https://github.com/PraveenKumar8919/eks-infra.git
cd eks-infra
```

**2. Create your tfvars file**
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your VPC ID, subnets, bucket names, domain
```

`terraform.tfvars` example:
```hcl
region         = "us-east-1"
cluster_name   = "eks-test-cluster"
domain_name    = "devopswithpraveen.online"
loki_s3_bucket = "your-loki-bucket-name"
vpc_id         = "vpc-xxxxxxxxxxxxxxxxx"
subnet_ids     = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
```

**3. Initialize Terraform**
```bash
terraform init \
  -backend-config="bucket=<your-state-bucket>" \
  -backend-config="key=eks-infra/state.tfstate" \
  -backend-config="region=us-east-1"
```

**4. Plan and apply**
```bash
terraform plan
terraform apply
```

**5. Update kubeconfig after apply**
```bash
aws eks update-kubeconfig --name eks-test-cluster --region us-east-1
kubectl get nodes
```

**6. Destroy when done**
```bash
terraform destroy
```

---

## GitHub Actions (CI/CD)

The workflow at `.github/workflows/infra.yml` runs automatically on every push to `main`.

```
Push to main
     ↓
terraform init   (uses TF_STATE_BUCKET secret for backend)
     ↓
terraform plan
     ↓
terraform apply
     ↓
Outputs exported to S3 state (read by eks-ansible config.yml)
```

### Required GitHub secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key | |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state | `my-tf-state-bucket` |
| `TF_VAR_VPC_ID` | VPC ID where the cluster will be created | `vpc-0abc1234` |
| `TF_VAR_SUBNET_IDS` | JSON array of subnet IDs (min 2, different AZs) | `["subnet-aaa","subnet-bbb"]` |
| `TF_VAR_LOKI_S3_BUCKET` | S3 bucket name for Loki log storage | `my-loki-logs` |

---

## Outputs

After `terraform apply`, these values are stored in the S3 Terraform state and read automatically by `eks-ansible`:

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API server URL |
| `kubeconfig_command` | Command to configure kubectl |
| `vpc_id` | VPC ID (passed to ALB controller) |
| `oidc_provider_arn` | OIDC provider ARN (used for IRSA) |
| `loki_iam_role_arn` | IAM role ARN for Loki → S3 access |
| `loki_s3_bucket` | S3 bucket name for Loki log storage |
| `acm_certificate_arn` | ACM wildcard cert ARN for HTTPS |
| `alb_controller_iam_role_arn` | IAM role ARN for ALB controller |
| `externaldns_iam_role_arn` | IAM role ARN for ExternalDNS |
| `domain_name` | Base domain (devopswithpraveen.online) |

---

## How it connects to eks-ansible

```
eks-infra (this repo)                      eks-ansible
─────────────────────                      ───────────
terraform apply
  → EKS cluster + Spot nodes   ──────────→ aws eks update-kubeconfig
  → ACM wildcard cert          ──────────→ Ingress TLS annotation
  → ALB controller IRSA role   ──────────→ ALB controller Helm values
  → ExternalDNS IRSA role      ──────────→ ExternalDNS Helm values
  → Loki IRSA role + S3 bucket ──────────→ Loki Helm values
  → writes outputs to S3 state ──────────→ config.yml reads state directly
```
