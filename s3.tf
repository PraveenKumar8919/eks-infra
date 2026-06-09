resource "aws_s3_bucket" "loki_storage" {
  bucket        = var.loki_s3_bucket
  force_destroy = true

  tags = {
    Environment = "test"
    Terraform   = "true"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_storage" {
  bucket = aws_s3_bucket.loki_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
