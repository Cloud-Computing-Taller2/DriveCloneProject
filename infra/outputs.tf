output "s3_bucket_name" {
  value = aws_s3_bucket.storage.bucket
}

output "sqs_queue_url" {
  value = aws_sqs_queue.main.url
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "iam_access_key_id" {
  value     = aws_iam_access_key.app_user_key.id
  sensitive = true
}

output "iam_secret_access_key" {
  value     = aws_iam_access_key.app_user_key.secret
  sensitive = true
}
