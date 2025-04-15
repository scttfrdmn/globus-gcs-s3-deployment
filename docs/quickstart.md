# Quick Start Guide

This guide provides concise steps to set up and deploy the Globus Connect Server S3 template.

## Prerequisites

1. **AWS Account Setup**:
   - AWS account with EC2, CloudFormation, IAM permissions
   - VPC with public subnet
   - EC2 key pair

2. **Globus Account Setup**:
   - Follow the complete instructions in [prerequisites.md](./prerequisites.md) to set up your Globus service account
   - ⚠️ **IMPORTANT**: The steps in the prerequisites document are **mandatory** and must be completed in the specified order
   - Create an S3 bucket in your AWS account that you want to connect to Globus

> **CRITICAL**: Before proceeding with deployment, you **must** complete the [Globus Service Account Setup](./prerequisites.md) process. This includes creating a project, registering a service account, making the service account a project admin, and granting subscription group access. Without these steps, your deployment will not function correctly, especially for S3 connector features.

## Deployment

### Option 1: CloudFormation Console

> **Note:** Quick Launch buttons have been temporarily removed while the template is being updated.
> Please use the AWS CLI deployment method (Option 2) below.

To deploy using the CloudFormation console:

1. Open the AWS CloudFormation console in your desired region
2. Choose "Create stack" > "With new resources (standard)" 
3. Select "Upload a template file" and upload the `globus-gcs-s3-template.yaml` file
4. Follow the prompts to fill in the parameters and create the stack

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
   - Review the deployment summary: `cat /home/ubuntu/deployment-summary.txt`
   - Verify that collections were created and permissions were set correctly
   - If needed, create additional collections using the helper scripts:
     ```bash
     # For S3 collections
     /home/ubuntu/create-s3-collection.sh "My New S3 Collection"
     
     # For POSIX collections
     /home/ubuntu/create-posix-collection.sh "My New POSIX Collection"
     ```

5. **Access your endpoint**:
   - Go to [app.globus.org/file-manager](https://app.globus.org/file-manager)
   - Search for your endpoint by name
   - Or use the collection URL from the deployment output

## Troubleshooting

- Run diagnostic script: `/home/ubuntu/diagnose-endpoint.sh`
- Check logs: `cat /home/ubuntu/globus-setup-complete.log`
- If endpoint is not visible in web interface, ensure a collection was created

For more detailed instructions, see [deployment.md](deployment.md).