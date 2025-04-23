# Globus Connect Server Installation Guide

This guide consolidates the prerequisites and deployment steps for setting up Globus Connect Server with S3 integration on AWS.

## Prerequisites

### AWS Account Requirements

| Requirement | Description |
|-------------|-------------|
| IAM Permissions | CloudFormation, EC2, S3, IAM |
| EC2 Key Pair | Existing key pair for SSH access |
| VPC | Public subnet with internet access |
| S3 Bucket | Existing or new bucket for S3 connector |

### Globus Account Requirements

| Requirement | Description | Required? |
|-------------|-------------|-----------|
| Globus Account | Account at [globus.org](https://www.globus.org/) | ✓ |
| Project ID | From Globus Auth Developer Console | ✓ |
| Client ID | Service credential UUID | ✓ |
| Client Secret | Service credential secret | ✓ |
| Owner Identity | Valid Globus identity (e.g., user@example.edu) | ✓ |
| Contact Email | Support contact visible to users | ✓ |
| Subscription ID | For S3 connector (e.g., "DEFAULT") | ✓ |

**Important:** Deployment requires Globus Connect Server 5.4.61+ (automatically verified).

## Service Account Configuration

Follow these steps to prepare your Globus environment:

1. **Create a Globus Project**
   - Navigate to [Globus Developer Settings](https://app.globus.org/settings/developers)
   - Click "Add Project"
   - Enter a name and contact email
   - Save the **Project ID**

2. **Create a Service Account**
   - In your project, click "Add..." → "Add App"
   - Select "Service Account Registration"
   - Provide an App Name (e.g., "CFN Service Account")
   - Save the **Client ID** and create a **Client Secret**

3. **Make the Service Account a Project Admin**
   - Navigate to [Globus Auth Developers](https://auth.globus.org/v2/web/developers)
   - Select your project
   - Click "Add" → "Add/remove admins"
   - Enter the Service Account Identity: `CLIENT_UUID@clients.auth.globus.org`
   - Click "Add as admin"

4. **Grant Subscription Group Access (for S3 Connector)**
   - Navigate to [Globus Groups](https://app.globus.org/groups)
   - Select your subscription group
   - Add the Service Account Identity to the group as Administrator

## Deployment Process

### Parameters to Collect

| Parameter | Value | Notes |
|-----------|-------|-------|
| KeyName | `your-key-pair` | EC2 key pair name |
| VpcId | `vpc-xxxxxxxx` | VPC ID |
| SubnetId | `subnet-xxxxxxxx` | Subnet ID |
| AvailabilityZone | `us-east-1a` | Matching subnet AZ |
| GlobusClientId | `your-client-uuid` | From service account |
| GlobusClientSecret | `your-client-secret` | From service account |
| GlobusProjectId | `your-project-id` | From project creation |
| GlobusOwner | `owner@example.com` | Valid identity |
| GlobusContactEmail | `support@example.com` | Support contact |
| GlobusDisplayName | `Your Endpoint Name` | Unique endpoint name |
| GlobusOrganization | `Your Organization` | Organization name |
| GlobusSubscriptionId | `your-subscription-id` | E.g., "DEFAULT" |
| S3BucketName | `your-s3-bucket` | Existing bucket name |

### AWS CLI Deployment

1. **Create parameters.json**:
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
   # Check current status
   aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text
   
   # Wait for completion
   aws cloudformation wait stack-create-complete --stack-name globus-gcs
   ```

### CloudFormation Console Deployment

1. Open the AWS CloudFormation console in your desired region
2. Choose "Create stack" > "With new resources (standard)"
3. Select "Upload a template file" and upload `globus-gcs-s3-template.yaml`
4. Fill in the parameters with values from your parameter collection
5. Check the "I acknowledge that AWS CloudFormation might create IAM resources" checkbox
6. Review and create the stack

## Verification

### Post-Deployment Verification

```bash
# Get stack outputs
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].Outputs" --output table

# Get public DNS or IP
PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)

# SSH to instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Check deployment summary
cat /home/ubuntu/deployment-summary.txt

# Verify Globus installation
globus-connect-server endpoint show
globus-connect-server storage-gateway list
```

### Accessing the Endpoint

1. Go to [app.globus.org/file-manager](https://app.globus.org/file-manager)
2. Search for your endpoint by name
3. Or find your endpoint ID in `/home/ubuntu/endpoint-uuid.txt`

## Cleaning Up Resources

**Important**: You must properly teardown Globus resources before deleting the CloudFormation stack.

```bash
# SSH to the instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Run the teardown script
bash /home/ubuntu/teardown-globus.sh

# After successful teardown, delete the stack
aws cloudformation delete-stack --stack-name globus-gcs
```

## Related Topics

- [Operations Guide](./operations.md) - Working with collections and transfers
- [Parameter Reference](./reference.md) - Complete parameter documentation
- [Troubleshooting Guide](./troubleshooting.md) - Common issues and solutions
