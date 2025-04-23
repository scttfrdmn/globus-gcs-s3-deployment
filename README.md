# Globus Connect Server with S3 Connector on AWS

This repository contains a CloudFormation template for deploying Globus Connect Server with Amazon S3 storage integration, enabling high-performance data transfers between S3 buckets and other Globus endpoints.

## Features

- **AWS CloudFormation Template**: Infrastructure-as-code deployment
- **S3 Integration**: Connect to S3 storage directly using instance credentials
- **Security**: IAM roles and policies with secure authentication
- **Automated Collection Creation**: Collections are automatically created during deployment
- **Version Validation**: Ensures compatibility with Globus Connect Server 5.4.61+

## Documentation

- [Installation Guide](./docs/installation.md) - Prerequisites and deployment instructions
- [Operations Guide](./docs/operations.md) - Working with collections and transfers
- [Parameter Reference](./docs/reference.md) - Complete parameter documentation
- [Troubleshooting Guide](./docs/troubleshooting.md) - Common issues and solutions
- [Quick Start Guide](./docs/quickstart.md) - Concise steps for deployment

## Prerequisites Overview

1. **AWS Account** with permissions for CloudFormation, EC2, S3, IAM
2. **Globus Account** with:
   - Service credentials (Client ID and Secret)
   - Valid Project ID where service account is an administrator
   - Owner identity username (e.g., user@example.edu)

See the [Installation Guide](./docs/installation.md) for complete prerequisites.

## Deployment Options

### AWS CLI

```bash
# Create the stack
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM

# Monitor deployment status
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text
```

### CloudFormation Console

1. Open the AWS CloudFormation console in your desired region
2. Choose "Create stack" > "With new resources (standard)"
3. Upload the `globus-gcs-s3-template.yaml` file
4. Fill in required parameters and create the stack

See the [Installation Guide](./docs/installation.md) for detailed deployment instructions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
