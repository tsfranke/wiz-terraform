# Wiz Infrastructure

Terraform configuration for AWS infrastructure including EKS, MongoDB, and security controls.

## Deploy

```bash
terraform init
terraform apply
```

## Components

- **EKS Cluster**: Kubernetes cluster with node group
- **MongoDB VM**: EC2 instance with MongoDB
- **Security**: Security Hub, Config, IAM Access Analyzer
- **Conformance Packs**: EKS and NIST compliance monitoring
