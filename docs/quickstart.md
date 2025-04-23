# Quick Start Guide

This guide provides the most concise steps to set up and deploy the Globus Connect Server S3 template.

## Prerequisites Summary

1. **AWS Resources**:
   - AWS account with EC2, CloudFormation, IAM permissions
   - VPC with public subnet
   - EC2 key pair
   - S3 bucket

2. **Globus Account Setup**:
   - Globus account
   - Service credentials (Client ID and Secret)
   - Project ID where service account is an admin
   - Subscription ID for S3 connector

⚠️ **IMPORTANT**: You **must** complete the [detailed prerequisites](./installation.md#service-account-configuration) before deployment.

## Deployment Steps

### 1. Prepare parameters.json

```json
[
  {"ParameterKey": "KeyName", "ParameterValue": "your-key-pair"},
  {"ParameterKey": "VpcId", "ParameterValue": "vpc-xxxxxxxx"},
  {"ParameterKey": "SubnetId", "ParameterValue": "subnet-xxxxxxxx"},
  {"ParameterKey": "AvailabilityZone", "ParameterValue": "us-east-1a"},
  {"ParameterKey": "GlobusClientId", "ParameterValue": "your-client-uuid"},
  {"ParameterKey": "GlobusClientSecret", "ParameterValue": "your-client-secret"},
  {"ParameterKey": "GlobusProjectId", "ParameterValue": "your-project-id"},
  {"ParameterKey": "GlobusOwner", "ParameterValue": "owner@example.com"},
  {"ParameterKey": "GlobusContactEmail", "ParameterValue": "support@example.com"},
  {"ParameterKey": "GlobusDisplayName", "ParameterValue": "Your Endpoint Name"},
  {"ParameterKey": "GlobusOrganization", "ParameterValue": "Your Organization"},
  {"ParameterKey": "GlobusSubscriptionId", "ParameterValue": "your-subscription-id"},
  {"ParameterKey": "S3BucketName", "ParameterValue": "your-s3-bucket"}
]
```

### 2. Deploy CloudFormation Stack

```bash
# Deploy stack
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM

# Monitor status
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text
```

### 3. Verify Deployment

```bash
# Get public DNS
PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)

# SSH to instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Check deployment summary
cat /home/ubuntu/deployment-summary.txt
```

### 4. Access Your Endpoint

1. Go to [app.globus.org/file-manager](https://app.globus.org/file-manager)
2. Search for your endpoint by name
3. Transfer files to/from your S3 bucket

## Next Steps

- [Installation Guide](./installation.md) - Complete deployment details
- [Operations Guide](./operations.md) - Working with collections and transfers
- [Troubleshooting Guide](./troubleshooting.md) - Common issues and solutions
