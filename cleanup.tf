resource "null_resource" "cleanup_alb" {
  depends_on = [module.vpc, module.eks]

  triggers = {
    vpc_id  = module.vpc.vpc_id
    cluster = var.cluster_name
    region  = var.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      echo "=== Pre-destroy cleanup: removing ALB-controller resources ==="

      # Delete all ingresses AND LoadBalancer-type Services so controller removes ALBs/NLBs
      kubectl delete ingress --all -A --ignore-not-found 2>/dev/null || true
      kubectl delete svc -A -l "app.kubernetes.io/managed-by=Helm" \
        --field-selector spec.type=LoadBalancer --ignore-not-found 2>/dev/null || true
      # Fallback: delete any remaining LB services by type
      for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        kubectl delete svc -n "$ns" --field-selector spec.type=LoadBalancer \
          --ignore-not-found 2>/dev/null || true
      done

      # Wait up to 5 min for all ELBs to be gone (with CLI timeouts to prevent hangs)
      echo "Waiting for load balancers to delete..."
      for i in $(seq 1 30); do
        count=$(aws elbv2 describe-load-balancers \
          --region "${self.triggers.region}" \
          --cli-connect-timeout 10 --cli-read-timeout 30 \
          --query 'length(LoadBalancers)' --output text 2>/dev/null || echo "0")
        [ "$count" = "0" ] && echo "  Load balancers gone." && break
        echo "  $count LB(s) still deleting... ($i/30)"
        sleep 10
      done

      # Delete leftover k8s-prefixed security groups
      sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query 'SecurityGroups[?starts_with(GroupName, `k8s-`)].GroupId' \
        --output text --region "${self.triggers.region}" \
        --cli-connect-timeout 10 --cli-read-timeout 30 2>/dev/null || true)
      for sg in $sgs; do
        echo "  Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg" \
          --region "${self.triggers.region}" \
          --cli-connect-timeout 10 --cli-read-timeout 30 2>/dev/null || true
      done

      echo "=== Pre-destroy cleanup complete ==="
    EOT
  }
}
