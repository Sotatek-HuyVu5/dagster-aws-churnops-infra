output "data_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  value = aws_s3_bucket.data.arn
}

output "models_bucket_name" {
  value = aws_s3_bucket.models.bucket
}

output "models_bucket_arn" {
  value = aws_s3_bucket.models.arn
}
