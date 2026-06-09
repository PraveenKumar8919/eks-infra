# eks-infra

Terraform code to provision an AWS EKS cluster and supporting infrastructure. This repo handles **pure AWS resources only** — no application deployments.

Application and Helm deployments live in [eks-ansible](https://github.com/PraveenKumar8919/eks-ansible).

---

## What this repo creates

```
AWS
├── EKS Cluster (Auto Mode)         ← managed control plane, AWS handles nodes
├── S3 Bucket                       ← Loki log storage
└── IAM Role (IRSA)                 ← lets Loki pod write to S3 without access keys
```

### Why EKS Auto Mode?
No node groups to manage. AWS automatically provisions and scales compute based on what your pods need. Ideal for a test/learning cluster.

### Why IRSA (IAM Roles for Service Accounts)?
Instead of putting AWS credentials inside a Kubernetes Secret, IRSA lets a pod assume an IAM role directly using Kubernetes identity. Loki uses this to read/write its S3 bucket securely.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Terraform >= 1.10](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| [AWS CLI](https://aws.amazon.com/cli/) | AWS authentication |
| An S3 bucket for Terraform state | Remote state storage |
| A VPC with at least 2 subnets in different AZs | EKS networking |

---

## Repository structure

```
eks-infra/
├── .github/workflows/infra.yml   # GitHub Actions — runs terraform apply on push
├── main.tf                        # EKS cluster definition
├── iam.tf                         # IRSA role for Loki → S3 access
├── s3.tf                          # S3 bucket for Loki log storage
├── provider.tf                    # AWS provider + S3 backend config
├── variables.tf                   # Input variables
├── outputs.tf                     # Outputs consumed by eks-ansible
├── terraform.tfvars.example       # Template — copy to terraform.tfvars for local use
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
# Edit terraform.tfvars with your VPC ID, subnets, bucket names
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
Outputs printed: cluster_name, loki_iam_role_arn, loki_s3_bucket
```

### Required GitHub secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret key |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |

---

## Outputs

After `terraform apply`, these values are available for the `eks-ansible` repo:

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API server URL |
| `loki_iam_role_arn` | IAM role ARN for Loki IRSA |
| `loki_s3_bucket` | S3 bucket name for Loki storage |
| `kubeconfig_command` | Command to configure kubectl |
| `oidc_provider_arn` | OIDC provider ARN |

---

## How it connects to eks-ansible

```
eks-infra (this repo)               eks-ansible
─────────────────────               ───────────
terraform apply
  → creates EKS cluster    ──────→  aws eks update-kubeconfig
  → creates IAM role ARN   ──────→  passed to Loki Helm values
  → creates S3 bucket      ──────→  passed to Loki Helm values
  → writes state to S3     ──────→  config.yml reads state directly
```
