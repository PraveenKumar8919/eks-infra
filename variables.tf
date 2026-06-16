variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "eks-test-cluster"
}

variable "domain_name" {
  description = "Root domain name managed in Route 53"
  default     = "devopswithpraveen.online"
}

variable "loki_s3_bucket" {
  description = "S3 bucket name for Loki log storage"
}

variable "create_nat_gateway" {
  description = "Create NAT gateway for private subnets. Set true when deploying EKS cluster."
  type        = bool
  default     = false
}
