terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.73.0"
    }
  }
}

provider "aws" {

  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sqs = var.localstack_endpoint
    iam = var.localstack_endpoint

    ### Why does it have to be the same endpoint for each service ?
    ## R: lstk inspect request headers and url path to route each API call to the corresponding internal srvice handler
  }
}

## Simple storage service
resource "aws_s3_bucket" "storage" {
  bucket        = var.bucket_name
  force_destroy = true # if terraform destroy fails, deletes anyway the bucket

}
## private bucket requirement
resource "aws_s3_bucket_public_access_block" "storage_block" {
  bucket                  = aws_s3_bucket.storage.id ## links the rule to the bucket
  block_public_acls       = true                     ## rejects any public access control list 
  block_public_policy     = true                     ## rejects any public policy
  ignore_public_acls      = true                     ## ignore access control list on objects inside the bucket, all private
  restrict_public_buckets = true                     ## blocks public cross account access even if public polocies existed on the bucket

}

resource "aws_s3_bucket_cors_configuration" "storage_cors" {
  bucket = aws_s3_bucket.storage.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = var.public_app_origin == "" ? var.frontend_origins : concat(var.frontend_origins, [var.public_app_origin])
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 days for debugging failed jobs
}

resource "aws_sqs_queue" "main" { ## why 2 ?
  name                       = var.queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10

  redrive_policy = jsonencode(
    {
      deadLetterTargetArn = aws_sqs_queue.dlq.arn
      maxReceiveCount     = 3
    }
  )

}

resource "aws_iam_user" "app_user" {
  name = "driveclone-app-user"
}

resource "aws_iam_access_key" "app_user_key" {
  user = aws_iam_user.app_user.name
}
resource "aws_iam_user_policy" "app_least_privilege" {
  name = "driveclone-least-privilege"
  user = aws_iam_user.app_user.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ObjectAccessOnly"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.storage.arn}/*"
      },
      {
        Sid    = "S3BucketListOnly"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.storage.arn
      },
      {
        Sid    = "SQSWorkerAndProducerAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.main.arn,
          aws_sqs_queue.dlq.arn
        ]
      }
    ]
  })


}
