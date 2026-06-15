variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "eks-test-cluster"
}

variable "domain_name" {
  description = "Root domain name managed in Route 53 (e.g. devopswithpraveen.online)"
  default     = "devopswithpraveen.online"
}

variable "loki_s3_bucket" {
  description = "S3 bucket name for Loki log storage"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster (minimum 2, different AZs)"
  type        = list(string)
}
