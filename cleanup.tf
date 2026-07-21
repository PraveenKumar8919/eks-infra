resource "null_resource" "cleanup_alb" {
  depends_on = [module.vpc, module.eks]

  triggers = {
    vpc_id  = module.vpc.vpc_id
    cluster = var.cluster_name
    region  = var.region
  }

  provisioner "local-exec" {
    when       = destroy
    interpreter = ["bash", "-c"]
    command    = <<-EOT
      echo "=== Pre-destroy cleanup: removing ALB-controller resources ==="

      # Delete all ingresses so ALB controller removes the ALBs
      kubectl delete ingress --all -A --ignore-not-found 2>/dev/null || true

      # Wait up to 5 min for ALBs to be gone
      echo "Waiting for ALBs to delete..."
      for i in $(seq 1 30); do
        count=$(aws elbv2 describe-load-balancers \
          --region "${self.triggers.region}" \
          --query 'length(LoadBalancers)' --output text 2>/dev/null || echo "0")
        [ "$count" = "0" ] && echo "  ALBs gone." && break
        echo "  $count ALB(s) still deleting... ($i/30)"
        sleep 10
      done

      # Delete leftover k8s-prefixed security groups (block subnet/VPC deletion)
      sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query 'SecurityGroups[?starts_with(GroupName, `k8s-`)].GroupId' \
        --output text --region "${self.triggers.region}" 2>/dev/null || true)
      for sg in $sgs; do
        echo "  Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg" \
          --region "${self.triggers.region}" 2>/dev/null || true
      done

      echo "=== Pre-destroy cleanup complete ==="
    EOT
  }
}
