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
   - **IMPORTANT**: This template requires Globus Connect Server 5.4.61 or higher
     - The deployment script will automatically detect and verify version compatibility
     - Supports various version formats including "package X.Y.Z" format
     - Provides detailed debug information for version detection and comparison

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
    "ParameterKey": "ScriptUrl",
    "ParameterValue": "https://raw.githubusercontent.com/scttfrdmn/globus-gcs-s3-deployment/main/scripts/globus-setup.sh"
  },
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
    "ParameterValue": "Your Globus Endpoint"
  },
  {
    "ParameterKey": "GlobusOrganization",
    "ParameterValue": "Your Organization Name"
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

> **Note**: The `ScriptUrl` parameter should point to the raw GitHub URL of the installation script. If you've forked this repository, update the URL to point to your fork. Alternatively, you could host the script on any other publicly accessible URL.

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
- Incompatible Globus Connect Server version (must be 5.4.61 or higher)
  - The script now properly handles various version output formats
  - Provides detailed version detection and comparison debugging
  - Common version output format "globus-connect-server, package X.Y.Z, cli A.B.C" is specifically supported
- Parameter handling issues with multi-word values (fixed with proper quoting)
- Duplicate endpoint names (now handled with check and reuse functionality)
- Key conversion failures when trying to convert credentials to a deployment key
  - Now includes detailed debugging output for key conversion
  - Provides automatic fallback methods if key conversion fails
  - Tries multiple command formats to maximize compatibility

### Debugging Environment Variables

The template includes debugging flags that can help troubleshoot deployment issues:

1. **DEBUG_SKIP_VERSION_CHECK**: Set to "true" in the template to bypass version compatibility checking. This is useful when your Globus version reports itself in an unusual format but is actually compatible.

2. **DEBUG_SKIP_DUPLICATE_CHECK**: Set to "true" to skip the check for existing endpoints with the same name, useful if you're testing the endpoint creation process or encountering duplicate check errors.

These variables can be modified in the CloudFormation template's UserData section or used directly when running the helper script manually:

If you see "WARNING - Failed to run module scripts-user" in the logs, this is likely a cloud-init warning that doesn't affect the deployment. The template includes robust error handling to continue despite these warnings. Check these files for diagnostic information:

```bash
# SSH into the instance first
cat /home/ubuntu/cloud-init-debug.log      # Detailed step-by-step deployment progress
cat /home/ubuntu/cloud-init-modules.log    # Information about cloud-init module issues
cat /var/log/cloud-init-output.log         # Standard cloud-init output
cat /var/log/user-data.log                 # User-data script output

# You can also try to manually run the Globus setup script if needed
sudo bash /home/ubuntu/run-globus-setup.sh

# To skip duplicate endpoint checks:
sudo DEBUG_SKIP_DUPLICATE_CHECK=true bash /home/ubuntu/run-globus-setup.sh

# To see detailed execution for debugging:
sudo bash -x /home/ubuntu/run-globus-setup.sh
```

The deployment script now includes:
- Detailed progress markers and validation steps
- Robust error handling that continues execution
- Multiple retry attempts for critical installation steps
- Comprehensive diagnostic information collection
- Version compatibility checks for different versions of Globus Connect Server
- Support for different command line parameter formats (both `--secret` and `--client-secret`)
- Checks for existing endpoints with the same name before deployment
- Ability to reuse existing endpoints rather than failing

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

## Cleaning Up Resources

When you delete the CloudFormation stack, the EC2 instance is retained by default (using `DeletionPolicy: Retain`). This allows you to manually clean up the Globus endpoint registration before terminating the instance:

```bash
# SSH into the instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Get the endpoint ID (either from show command or from the saved file if using existing endpoint)
if [ -f /home/ubuntu/existing-endpoint-id.txt ]; then
  ENDPOINT_ID=$(cat /home/ubuntu/existing-endpoint-id.txt)
else
  ENDPOINT_ID=$(globus-connect-server endpoint show | grep -E 'UUID|ID' | awk '{print $2}' | head -1)
fi

# Delete the endpoint from Globus
[ -n "$ENDPOINT_ID" ] && globus-connect-server endpoint delete

# Verify the endpoint was deleted
globus-connect-server endpoint show
```

After manually deleting the Globus endpoint, you can terminate the EC2 instance through the AWS Console or using:

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-stacks --stack-name globus-gcs --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)

# Terminate the instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

This manual cleanup step ensures that the Globus endpoint is properly deleted from Globus's systems.

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