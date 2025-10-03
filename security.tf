# Security Hub - Detective Control
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
}

# IAM Access Analyzer - Preventative Control  
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "wiz-access-analyzer"
  type          = "ACCOUNT"
}

# Config - Detective Control
resource "aws_config_configuration_recorder" "main" {
  name     = "wiz-config-recorder"
  role_arn = "arn:aws:iam::148761666891:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  recording_group {
    all_supported = false
    resource_types = [
      "AWS::EC2::Instance",
      "AWS::S3::Bucket",
      "AWS::IAM::Role",
      "AWS::EKS::Cluster"
    ]
  }
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_conformance_pack" "eks" {
  name            = "EKS"
  template_s3_uri = "s3://aws-config-conformance-packs-us-east-1/Operational-Best-Practices-for-Amazon-EKS.yaml"
  depends_on      = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_conformance_pack" "nist" {
  name            = "NIST"
  template_s3_uri = "s3://aws-config-conformance-packs-us-east-1/NIST-800-53-Rev5.yaml"
  depends_on      = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_delivery_channel" "main" {
  name           = "wiz-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.bucket
}

resource "aws_s3_bucket" "config" {
  bucket        = "wiz-config-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
