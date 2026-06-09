output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "loki_iam_role_arn" {
  value = aws_iam_role.loki.arn
}

output "loki_s3_bucket" {
  value = aws_s3_bucket.loki_storage.bucket
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
