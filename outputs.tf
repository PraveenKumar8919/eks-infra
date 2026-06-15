output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "vpc_id" {
  value = var.vpc_id
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

output "acm_certificate_arn" {
  value = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "alb_controller_iam_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "externaldns_iam_role_arn" {
  value = aws_iam_role.externaldns.arn
}

output "domain_name" {
  value = var.domain_name
}
