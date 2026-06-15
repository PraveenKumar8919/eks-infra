module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = "1.33"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  eks_managed_node_groups = {
    spot = {
      # Multiple instance types = more Spot capacity pools = fewer interruptions
      # t3/t3a.xlarge: 4 vCPU 16GB  |  m5/m5a.xlarge: 4 vCPU 16GB
      instance_types = [
        "t3.xlarge",
        "t3a.xlarge",
        "m5.xlarge",
        "m5a.xlarge",
      ]

      capacity_type = "SPOT"

      min_size     = 2
      max_size     = 5
      desired_size = 2

      labels = {
        role      = "spot-worker"
        lifecycle = "spot"
      }
    }
  }

  cluster_addons = {
    # Provides storage provisioner — required for Prometheus PersistentVolumeClaims
    aws-ebs-csi-driver = {
      service_account_role_arn = aws_iam_role.ebs_csi.arn
      most_recent              = true
    }
  }

  tags = {
    Environment = "test"
    Terraform   = "true"
  }
}
