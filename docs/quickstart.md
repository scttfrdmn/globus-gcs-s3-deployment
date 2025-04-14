# Quick Start Guide

This guide provides concise steps to set up and deploy the Globus Connect Server S3 template.

## Prerequisites

1. **AWS Account Setup**:
   - AWS account with EC2, CloudFormation, IAM permissions
   - VPC with public subnet
   - EC2 key pair

2. **Globus Account Setup**:
   - Create account at [globus.org](https://www.globus.org/)
   - Get subscription ID (REQUIRED for S3 connector)
     - Your organization needs a Globus subscription
     - Either use "DEFAULT" or a specific subscription ID
     - You must have subscription manager role or coordinate with one
   - Create S3 bucket

3. **Globus Service Identity Setup**:
   - Go to [Globus Developer Console](https://app.globus.org/settings/developers)
   - Create a project, register an application
   - Record Client UUID and Client Secret
   - Add service identity as project admin: `CLIENT_UUID@clients.auth.globus.org`
   - Record Project ID

## Deployment

### Option 1: CloudFormation Console (Quick Launch)

Click on a region-specific launch button to deploy the template directly through the AWS CloudFormation console:

| Region | Launch Button |
|--------|--------------|
| **US East (N. Virginia)** | [![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create/review?templateURL=https://raw.githubusercontent.com/scttfrdmn/globus-gcs-s3-deployment/main/globus-gcs-s3-template.yaml&stackName=globus-gcs) |
| **US East (Ohio)** | [![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-2#/stacks/create/review?templateURL=https://raw.githubusercontent.com/scttfrdmn/globus-gcs-s3-deployment/main/globus-gcs-s3-template.yaml&stackName=globus-gcs) |
| **US West (Oregon)** | [![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create/review?templateURL=https://raw.githubusercontent.com/scttfrdmn/globus-gcs-s3-deployment/main/globus-gcs-s3-template.yaml&stackName=globus-gcs) |

* Make sure to complete the prerequisites first and have all required parameters ready
* Fill in the parameter form with your specific Globus credentials and AWS resources
* Check the "I acknowledge that AWS CloudFormation might create IAM resources" checkbox

### Option 2: AWS CLI

1. **Prepare parameters.json**:
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
     {"ParameterKey": "GlobusDisplayName", "ParameterValue": "Your Unique Endpoint Name"},
     {"ParameterKey": "GlobusOrganization", "ParameterValue": "Your Organization"},
     {"ParameterKey": "GlobusSubscriptionId", "ParameterValue": "your-subscription-id"},
     {"ParameterKey": "S3BucketName", "ParameterValue": "your-s3-bucket"}
   ]
   ```

2. **Deploy CloudFormation Stack**:
   ```bash
   aws cloudformation create-stack \
     --stack-name globus-gcs \
     --template-body file://globus-gcs-s3-template.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_IAM
   ```

3. **Monitor deployment**:
   ```bash
   aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text
   ```

4. **Post-Deployment Configuration**:
   - SSH into the instance: `ssh -i your-key.pem ubuntu@<instance-ip>`
   - If S3 collection wasn't created automatically:
     ```bash
     /home/ubuntu/create-s3-collection.sh your-s3-bucket
     ```
   - The collection URL will appear in the output

5. **Access your endpoint**:
   - Go to [app.globus.org/file-manager](https://app.globus.org/file-manager)
   - Search for your endpoint by name
   - Or use the collection URL from the deployment output

## Troubleshooting

- Run diagnostic script: `/home/ubuntu/diagnose-endpoint.sh`
- Check logs: `cat /home/ubuntu/globus-setup-complete.log`
- If endpoint is not visible in web interface, ensure a collection was created

For more detailed instructions, see [deployment.md](deployment.md).