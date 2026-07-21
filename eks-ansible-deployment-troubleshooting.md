# EKS + Ansible Deployment Troubleshooting — 2026-07-20

End-to-end session: provisioned EKS cluster from scratch, deployed LGTM observability stack + Roboshop via Ansible/Helm.

---

## Infrastructure Summary

| Repo | Purpose |
|------|---------|
| `eks-infra` (Terraform) | VPC, EKS cluster, IAM roles, ACM cert |
| `eks-ansible` (Ansible + Helm) | ALB controller, ExternalDNS, Loki, Prometheus/Grafana, Alloy, Roboshop |

**Cluster:** `eks-test-cluster` | Region: `us-east-1` | Nodes: 2x Spot (`t3.large` family)

---

## Issue 1 — `community.general.yaml` callback plugin removed

**Symptom:**
```
[ERROR]: The 'community.general.yaml' callback plugin has been removed.
```
Ansible playbook failed immediately before any task ran.

**Root Cause:**
`ansible.cfg` had `stdout_callback = yaml` which loaded the `community.general.yaml` callback plugin. This plugin was removed in `community.general` v12.0.0.

**Fix — `ansible.cfg`:**
```ini
# Before
stdout_callback = yaml

# After
stdout_callback   = default
result_format     = yaml
```

---

## Issue 2 — `cluster_name` is undefined

**Symptom:**
```
'cluster_name' is undefined
roles/aws-load-balancer-controller/tasks/main.yml:16
  clusterName: "{{ cluster_name }}"
```

**Root Cause:**
No inventory file existed. Ansible was using "implicit localhost" which does **not** load `group_vars/`. The variable `cluster_name` is defined in `group_vars/all.yml` but was never loaded.

**Fix:**
1. Created `hosts` file at repo root:
```ini
[all]
localhost ansible_connection=local
```
2. Set inventory in `ansible.cfg`:
```ini
inventory = ./hosts
```

> **Key rule:** Ansible loads `group_vars/` relative to the inventory file location. The `hosts` file must be at the same level as the `group_vars/` directory.

---

## Issue 3 — Loki `chunks-cache` StatefulSet timeout

**Symptom:**
```
Error: resource StatefulSet/loki-live/loki-chunks-cache not ready. status: InProgress, message: Ready: 0/1
context deadline exceeded
```
Loki Helm install timed out after 5 minutes.

**Root Cause:**
Newer Loki chart versions (v3.x / chart 6.x+) deploy a memcached `chunks-cache` StatefulSet by default even in `SingleBinary` mode. This component took longer than the 5m timeout.

**Fix — `roles/loki/tasks/main.yml`:**
```yaml
# Disable cache components not needed for POC
chunksCache:  { enabled: false }
resultsCache: { enabled: false }

# Also increase timeout
timeout: "10m"  # was 5m
```

---

## Issue 4 — Loki PVC unbound (no default StorageClass)

**Symptom:**
```
pod has unbound immediate PersistentVolumeClaims
0/2 nodes are available: Preemption is not helpful for scheduling
```
`loki-0` pod stuck in `Pending` state.

**Root Cause:**
The `gp2` StorageClass existed but was **not set as the default**. Loki's PVC had no `storageClassName` specified, so it couldn't bind.

```bash
kubectl get storageclass
# NAME   PROVISIONER             VOLUMEBINDINGMODE
# gp2    kubernetes.io/aws-ebs   WaitForFirstConsumer   # no (default) label
```

**Fix — two parts:**

1. One-time cluster patch (only needed if Loki was already deployed without the pre_task):
```bash
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl delete pvc storage-loki-0 -n loki-live   # delete stale unbound PVC
```

2. Made it permanent in `playbooks/observability.yml` so future deploys work automatically:
```yaml
pre_tasks:
  - name: Set gp2 as default StorageClass
    kubernetes.core.k8s:
      state: patched
      kind: StorageClass
      name: gp2
      definition:
        metadata:
          annotations:
            storageclass.kubernetes.io/is-default-class: "true"
```

---

## Issue 5 — `vault_grafana_admin_password` is undefined

**Symptom:**
```
[ERROR]: 'vault_grafana_admin_password' is undefined
roles/prometheus/tasks/main.yml — Install kube-prometheus-stack
```

**Root Cause:**
`group_vars/vault.yml` is an Ansible Vault-encrypted file. The `ANSIBLE_VAULT_PASSWORD` GitHub secret either had the wrong value or the vault file was encrypted with a different password. Result: vault variables were never decrypted/loaded.

**Fix:**
Removed Ansible Vault entirely for this POC cluster. Replaced vault variable references in `group_vars/all.yml` with env var lookups:

```yaml
# Before
grafana_admin_password: "{{ vault_grafana_admin_password }}"

# After
grafana_admin_password: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') | default('DevOps@2025', true) }}"
```

Updated `config.yml` workflow to pass the GitHub secret as an env var and removed the vault password file steps:
```yaml
- name: Deploy observability stack
  env:
    GRAFANA_ADMIN_PASSWORD: ${{ secrets.GRAFANA_ADMIN_PASSWORD }}
  run: |
    ansible-playbook playbooks/observability.yml \
      -e "loki_iam_role_arn=..."
```

---

## Issue 6 — ALB Controller `AccessDenied: SetRulePriorities`

**Symptom:**
```
AccessDenied: not authorized to perform: elasticloadbalancing:SetRulePriorities
```
Grafana and Prometheus Ingresses had no ALB address. Only Loki's ingress was provisioned.

**Root Cause:**
All three ingresses (Loki, Grafana, Prometheus) share the same ALB group (`observability`). When multiple ingresses use the same ALB group, the ALB controller needs `SetRulePriorities` to manage listener rule ordering. This permission was missing from the IAM policy.

**Fix — `policies/alb-controller-policy.json`:**
```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:SetWebAcl",
    "elasticloadbalancing:ModifyListener",
    "elasticloadbalancing:AddListenerCertificates",
    "elasticloadbalancing:RemoveListenerCertificates",
    "elasticloadbalancing:ModifyRule",
    "elasticloadbalancing:SetRulePriorities"   ← added
  ],
  "Resource": "*"
}
```

Applied the change and restarted the controller:
```bash
terraform apply -target=aws_iam_policy.alb_controller -var="loki_s3_bucket=ppattirik-loki-logs" -var="create_nat_gateway=true" -auto-approve
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

## Final State — All Working

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | https://grafana.devopswithpraveen.online | `admin` / (GRAFANA_ADMIN_PASSWORD secret) |
| Prometheus | https://prometheus.devopswithpraveen.online | — |
| Loki | https://loki.devopswithpraveen.online | — |
| Roboshop | via `kubectl get ingress -n roboshop` | — |

**All pods running:**
```
loki-live     loki-0                    2/2   Running
monitoring    alloy-*                   2/2   Running  (x2 nodes)
roboshop      catalogue, cart, user...  1/1   Running  (10 services)
```

---

---

## Issue 7 — Subnet `DependencyViolation` during `terraform destroy`

**Symptom:**
```
Error: deleting EC2 Subnet (subnet-xxx): DependencyViolation: The subnet has dependencies and cannot be deleted.
```
`terraform destroy` hangs for hours then fails. Subnets cannot be deleted.

**Root Cause:**
The ALB controller creates ALBs in response to Kubernetes Ingress objects. These ALBs are **not managed by Terraform** — Terraform has no record of them and cannot delete them. When `terraform destroy` tries to remove the VPC subnets, AWS rejects it because the ALB's ENIs are still attached to those subnets.

**Fix — always delete ALBs before `terraform destroy`:**

```bash
# Step 1: Delete all Kubernetes ingresses (ALB controller will remove the ALBs)
kubectl delete ingress --all -A

# Step 2: Wait for ALBs to be gone
until [ $(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text) -eq 0 ]; do
  echo "Waiting for ALBs to delete..."; sleep 10
done
echo "ALBs deleted — safe to run terraform destroy"

# Step 3: Now run terraform destroy
terraform destroy -var="loki_s3_bucket=ppattirik-loki-logs" -var="create_nat_gateway=true"
```

If you already ran `terraform destroy` and it failed with DependencyViolation:
```bash
# Delete ALBs directly via AWS CLI
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output table
aws elbv2 delete-load-balancer --load-balancer-arn <arn>

# Force-unlock stale state lock (from the killed terraform process)
terraform force-unlock -force <lock-id>

# Re-run destroy
terraform destroy -var="loki_s3_bucket=ppattirik-loki-logs" -var="create_nat_gateway=true"
```

> **Permanent fix implemented:** `cleanup.tf` in eks-infra contains a `null_resource` with a `when = destroy` provisioner. It has `depends_on = [module.vpc, module.eks]` so it is destroyed FIRST (reverse dependency order), running the cleanup automatically before Terraform touches any subnets. Just run `terraform destroy` normally — no manual pre-steps needed.
>
> `destroy.sh` exists as a last resort if the provisioner fails — it does the full cleanup manually then runs terraform destroy and recreates the VPC.

---

## Commits Made Today

| Repo | Commit | Fix |
|------|--------|-----|
| eks-ansible | `68ba8ea` | Fix ansible.cfg: replace removed community.general.yaml callback |
| eks-ansible | `fb4b083` | Add inventory file so group_vars/all.yml variables load |
| eks-ansible | `8aa5ce8` | Move hosts to repo root so group_vars/ is adjacent |
| eks-ansible | `7419de6` | Disable Loki chunks/results cache, increase timeout to 10m |
| eks-ansible | `83189cb` | Set gp2 as default StorageClass via Ansible pre_task |
| eks-ansible | `f6abb02` | Replace Ansible Vault with env var lookups for POC passwords |
| eks-infra   | `8b9e331` | Add SetRulePriorities to ALB controller IAM policy |
