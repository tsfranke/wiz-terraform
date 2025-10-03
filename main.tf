provider "aws" {
  region = "us-east-1"
}

# Use existing Wizlabs-VPC
data "aws_vpc" "main" {
  id = "vpc-08c1881e02c98ab3f"
}

# Fetch all subnets in the VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Get subnet details
data "aws_subnet" "all" {
  for_each = toset(data.aws_subnets.all.ids)
  id       = each.value
}

# Filter private subnets (no public IP mapping)
locals {
  private_subnets = [
    for subnet in data.aws_subnet.all : subnet
    if !subnet.map_public_ip_on_launch
  ]
  public_subnets = [
    for subnet in data.aws_subnet.all : subnet
    if subnet.map_public_ip_on_launch
  ]
}

# Security Groups
resource "aws_security_group" "mongodb_vm" {
  name_prefix = "mongodb-vm-sg"
  vpc_id      = data.aws_vpc.main.id
  
  # SSH from anywhere (INTENTIONAL WEAKNESS)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # MongoDB from private subnets only
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [for subnet in local.private_subnets : subnet.cidr_block]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for MongoDB VM (OVERLY PERMISSIVE)
resource "aws_iam_role" "mongodb_vm" {
  name = "mongodb-vm-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# INTENTIONAL WEAKNESS: Overly permissive policy
resource "aws_iam_role_policy" "mongodb_vm_policy" {
  name = "mongodb-vm-policy"
  role = aws_iam_role.mongodb_vm.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "s3:*",
          "iam:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "mongodb_vm" {
  name = "mongodb-vm-profile"
  role = aws_iam_role.mongodb_vm.name
}

# S3 Bucket for backups (PUBLIC READ)
resource "aws_s3_bucket" "backups" {
  bucket = "wiz-mongodb-backups-${random_string.suffix.result}"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  # INTENTIONAL WEAKNESS: Allow public access
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "backups_public" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.backups.arn
      }
    ]
  })
}

# MongoDB VM with outdated Ubuntu
resource "aws_instance" "mongodb" {
  ami                    = "ami-0c7217cdde317cfec"  # Ubuntu 20.04 (outdated)
  instance_type          = "t3.medium"
  subnet_id              = local.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.mongodb_vm.id]
  iam_instance_profile   = aws_iam_instance_profile.mongodb_vm.name
  key_name               = aws_key_pair.mongodb.key_name
  
  user_data = base64encode(templatefile("${path.module}/mongodb-userdata.sh", {
    bucket_name = aws_s3_bucket.backups.bucket
  }))
  
  tags = {
    Name = "mongodb-server"
  }
}

# Key pair for SSH access
resource "aws_key_pair" "mongodb" {
  key_name   = "mongodb-key"
  public_key = file("${path.module}/mongodb-key.pub")
}

# Random string for unique names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Outputs
output "mongodb_public_ip" {
  value = aws_instance.mongodb.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.backups.bucket
}

output "vpc_id" {
  value = data.aws_vpc.main.id
}

output "private_subnet_ids" {
  value = [for subnet in local.private_subnets : subnet.id]
}
