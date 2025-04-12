# Deployment Steps for Globus Connect Server with S3 Connector

## Prerequisites

1. AWS Account and Permissions:

   - IAM permissions for CloudFormation, EC2, S3, IAM
   - EC2 key pair for SSH access
   - Existing VPC with public subnet (internet access required)

2. Globus Account and Registration:

   - Create account at [globus.org](https://www.globus.org/)
   - Register application in [Globus Developer Console](https://developers.globus.org/)
   - Obtain Client ID and Client Secret
   - (Optional) Obtain Subscription ID for connector support

3. S3 Storage:

   - Create S3 bucket or identify existing bucket
   - Note the bucket name

## Template Options

### Deployment Type

- **Integration**: Dynamic IP, suitable for testing
- **Production**: Includes Elastic IP, better for stable endpoints

### Authentication

- **Globus**: Federation-based auth (recommended)
- **MyProxy**: Local account-based auth (legacy)

### Connectors (requires subscription)

- **S3 Connector**: Connect to S3 bucket (the only connector type supported in this template)

### Network Options

- **VPC**: Where to deploy the server
- **Subnet**: Requires public internet access
- **Availability Zone**: Single AZ deployment
- **Force Elastic IP**: Optional static IP for integration deployments

## Deployment Steps

### 1. Prepare parameters file

```json
[
  {
    "ParameterKey": "DeploymentType",
    "ParameterValue": "Production"
  },
  {
    "ParameterKey": "InstanceType",
    "ParameterValue": "m6i.xlarge"
  },
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "your-key-pair"
  },
  {
    "ParameterKey": "AvailabilityZone",
    "ParameterValue": "us-east-1a"
  },
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "vpc-xxxxxxxx"
  },
  {
    "ParameterKey": "SubnetId",
    "ParameterValue": "subnet-xxxxxxxx"
  },
  {
    "ParameterKey": "AuthenticationMethod",
    "ParameterValue": "Globus"
  },
  {
    "ParameterKey": "DefaultAdminIdentity",
    "ParameterValue": "your-email@example.org"
  },
  {
    "ParameterKey": "GlobusClientId",
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusClientSecret",
    "ParameterValue": "xxxxxxxxxxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusDisplayName",
    "ParameterValue": "Your-Globus-Endpoint"
  },
  {
    "ParameterKey": "GlobusSubscriptionId",
    "ParameterValue": "xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "EnableS3Connector",
    "ParameterValue": "true"
  },
  {
    "ParameterKey": "S3BucketName",
    "ParameterValue": "your-globus-bucket"
  }
]
```

### 2. Deploy the CloudFormation stack

```bash
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM
```

### 3. Monitor deployment

```bash
# Check stack creation status - outputs just the status without quotes
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text

# Wait for complete status
aws cloudformation wait stack-create-complete --stack-name globus-gcs
```

## Verification Steps

### 1. Retrieve stack outputs

```bash
# Get all outputs with details
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].Outputs" --output table

# Get just the output values (for scripting)
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}" --output table
```

Key outputs include:

- InstanceId
- ElasticIP or PublicIP
- PublicAddress (for Globus redirection)
- AuthenticationConfiguration
- ConnectorsEnabled

If deployment fails, first check the CloudFormation events for error information:

```bash
# Show any failed resources in a readable table format
aws cloudformation describe-stack-events --stack-name globus-gcs --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].{Resource:LogicalResourceId,Type:ResourceType,Reason:ResourceStatusReason}" --output table
```

Common issues include:
- Exceeding UserData script size limits (now fixed with optimized script)
- Network configuration issues preventing package installation
- Incorrect parameters such as bucket names or availability zones

If you see "WARNING - Failed to run module scripts-user" in the logs, this is likely a cloud-init warning that doesn't affect the deployment. The template includes robust error handling to continue despite these warnings. Check these files for diagnostic information:

```bash
# SSH into the instance first
cat /home/ubuntu/cloud-init-debug.log      # Detailed step-by-step deployment progress
cat /home/ubuntu/cloud-init-modules.log    # Information about cloud-init module issues
cat /var/log/cloud-init-output.log         # Standard cloud-init output
cat /var/log/user-data.log                 # User-data script output

# You can also try to manually run the Globus setup script if needed
sudo bash /home/ubuntu/run-globus-setup.sh
```

The deployment script now includes:
- Detailed progress markers and validation steps
- Robust error handling that continues execution
- Multiple retry attempts for critical installation steps
- Comprehensive diagnostic information collection

### 2. SSH into the instance

```bash
# Get the public address (cleaner approach with --output text)
PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)

# Alternative way to get public IP if you prefer that
PUBLIC_IP=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='ElasticIP' || OutputKey=='PublicIP'].OutputValue" --output text)

# Connect via SSH using DNS name
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Or connect using IP if you prefer
# ssh -i your-key-pair.pem ubuntu@$PUBLIC_IP
```

### 3. Check Globus installation

```bash
# Check server status
systemctl status globus-gridftp-server

# Show endpoint details
globus-connect-server endpoint show

# List configured connectors
globus-connect-server storage-gateway list
```

### 4. Verify access policies (if using Globus auth)

```bash
# List access policies
globus-connect-server acl list
```

### 5. Verify through Globus web interface

1. Go to [app.globus.org](https://app.globus.org/)
2. Log in with your Globus account
3. Navigate to "Collections" > "Your Collections"
4. Find your endpoint name
5. Confirm you can browse and transfer files

## Post-Deployment Configuration

### Additional access policies (if needed)

```bash
# Grant a user or group access to specific path
globus-connect-server acl create \
  --permissions read,write \
  --principal "user@example.org" \
  --path "/s3_storage/project/"
```

### Adding mapped collections (if needed)

```bash
# Create a mapped collection for specific data subsets
globus-connect-server mapped-collection create \
  --display-name "Project Data" \
  --storage-gateway-id s3_storage \
  --root-path "/project-data/"
```

This complete deployment process gives you a fully functional Globus Connect Server with S3 connector, properly configured authentication, and initial access controls.

## Deployment with Command Line Parameters

```bash
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=AuthenticationMethod,ParameterValue=Globus \
    ParameterKey=DefaultAdminIdentity,ParameterValue=admin@yourdomain.org
```