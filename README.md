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

## Deployment Features

The CloudFormation template includes the following reliability features:

- **Robust Error Handling**: Comprehensive error handling in all deployment steps
- **Resource Signaling**: Proper CloudFormation resource signaling with timeouts
- **S3 Bucket Validation**: Verifies S3 bucket existence before attempting connections
- **IAM Permission Controls**: Appropriate IAM permissions for all operations
- **Deployment Logs**: Detailed logging for troubleshooting
- **Admin Setup Retries**: Automatic retry logic for key configuration steps
- **Deployment Summary**: Generates a deployment summary file on the instance for quick reference

## Platform Configuration

The template deploys Globus Connect Server with the following configuration:

1. **Operating System**: Ubuntu Server 22.04 LTS
2. **Authentication**: Uses Globus Auth by default (configurable to MyProxy)
3. **Networking**: The template ensures the Globus Connect Server is publicly accessible through one of two approaches:
   - **For Production Deployments**: Uses an Elastic IP address for persistent, static public IP
   - **For Integration Deployments**: Either:
     - Uses an Elastic IP if `ForceElasticIP` is set to "true"
     - Automatically assigns a public IP address to the instance

This ensures that Globus can communicate with the server regardless of deployment type, which is essential for Globus Connect Server functionality.

## SSH Access

To connect to the deployed server:

```bash
ssh -i /path/to/your/key.pem ubuntu@<PUBLIC-IP-ADDRESS>
```

Important logs and resources on the server:
- Deployment summary: `/home/ubuntu/deployment-summary.txt`
- Installation logs: `/var/log/user-data.log` and `/var/log/cloud-init-output.log`
- Globus-specific logs: `/var/log/globus-setup.log`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.