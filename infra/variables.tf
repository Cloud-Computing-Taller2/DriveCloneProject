# Parameterizes names and frontend origins.
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "bucket_name" {
  type    = string
  default = "driveclone-storage"
}

variable "queue_name" {
  type    = string
  default = "driveclone-jobs"
}

variable "frontend_origins" {
  type    = list(string)
  default = ["http://localhost", "http://localhost:80", "http://localhost:8080", "http://localhost:5173"]
}

# Cloudflare Tunnel hostname for presigned-URL CORS; empty until the demo.
variable "public_app_origin" {
  type    = string
  default = ""
}
