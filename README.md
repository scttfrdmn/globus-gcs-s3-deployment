# Globus Connect Server with S3 Connector on AWS

This repository contains a CloudFormation template for deploying Globus Connect Server with Amazon S3 storage integration. This solution enables high-performance data transfers between S3 buckets and other Globus endpoints.

## Features

- **AWS CloudFormation Template**: Infrastructure-as-code deployment
- **S3 Integration**: Connect S3 buckets to the Globus ecosystem
- **Security**: IAM roles and policies for secure access
- **Flexible Authentication**: Support for Globus Auth federation
- **Optional Connectors**: Support for POSIX and Google Drive connectors
- **Production & Testing Modes**: Configurable deployment types

## Prerequisites

1. **AWS Account and Permissions**:
   - IAM permissions for CloudFormation, EC2, S3, IAM
   - EC2 key pair for SSH access
   - Existing VPC with public subnet

2. **Globus Account and Registration**:
   - Account at [globus.org](https://www.globus.org/)
   - Application registered in [Globus Developer Console](https://developers.globus.org/)
   - Client ID and Client Secret
   - (Optional) Subscription ID for connector support

3. **S3 Storage**:
   - Existing S3 bucket or plan to create one

## Documentation

The repository includes detailed documentation on deploying and using Globus Connect Server with S3:

- [Deployment Guide](./docs/deployment.md) - Step-by-step instructions for deploying the solution
- [CLI Operations](./docs/cli-operations.md) - How to use the Globus CLI for file transfers
- [Globus Groups](./docs/groups.md) - Managing access through Globus Groups
- [Collection Types](./docs/collections.md) - Understanding Globus collections and S3 integration

## Getting Started

1. Clone this repository:
   ```
   git clone https://github.com/scttfrdmn/globus-gcs-s3-deployment.git
   ```

2. Review the deployment documentation in the docs directory.

3. Deploy using CloudFormation:
   ```bash
   aws cloudformation create-stack \
     --stack-name globus-gcs \
     --template-body file://globus-gcs-s3-template.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_IAM
   ```

   Note: Boolean parameters in the template (like EnableS3Connector) must be specified as strings:
   ```json
   {
     "ParameterKey": "EnableS3Connector",
     "ParameterValue": "true"
   }
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.