module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = "1.33"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    spot = {
      instance_types = [
        "t3.large",   # 2 vCPU  8 GB
        "t3a.large",  # 2 vCPU  8 GB  AMD
        "t3.xlarge",  # 4 vCPU 16 GB
        "t3a.xlarge", # 4 vCPU 16 GB  AMD
        "m5.large",   # 2 vCPU  8 GB
        "m5a.large",  # 2 vCPU  8 GB  AMD
        "m5.xlarge",  # 4 vCPU 16 GB
        "m5a.xlarge", # 4 vCPU 16 GB  AMD
        "m4.large",   # 2 vCPU  8 GB
        "r5a.large",  # 2 vCPU 16 GB
      ]

      capacity_type = "SPOT"

      min_size     = 2
      max_size     = 5
      desired_size = 2

      timeouts = {
        create = "20m"
        update = "20m"
        delete = "15m"
      }

      labels = {
        role      = "spot-worker"
        lifecycle = "spot"
      }
    }
  }

  addons = {
    # before_compute = true installs these BEFORE any EC2 node launches.
    # Without this, nodes come up with no CNI and stay NotReady forever.
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent    = true
      before_compute = true
    }
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
