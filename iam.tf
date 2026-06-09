data "aws_iam_policy_document" "loki_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:loki-live:loki"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = "${var.cluster_name}-loki"
  assume_role_policy = data.aws_iam_policy_document.loki_assume_role.json

  tags = {
    Environment = "test"
    Terraform   = "true"
  }
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = [
      aws_s3_bucket.loki_storage.arn,
      "${aws_s3_bucket.loki_storage.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "loki_s3" {
  name   = "loki-s3-access"
  role   = aws_iam_role.loki.id
  policy = data.aws_iam_policy_document.loki_s3.json
}
