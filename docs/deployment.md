# Deployment Steps for Globus Connect Server with S3 Connector

## Prerequisites

1. AWS Account and Permissions:

   - IAM permissions for CloudFormation, EC2, S3, IAM
   - EC2 key pair for SSH access
   - Existing VPC with public subnet (internet access required)

2. Globus Account and Registration:

   - Create account at [globus.org](https://www.globus.org/)
   - Register application in [Globus Developer Console](https://developers.globus.org/)
   - Obtain Client ID and Client Secret as service credentials
   - (Optional) Obtain Subscription ID for connector support
   - **IMPORTANT**: This template requires Globus Connect Server 5.4.61 or higher
     - The deployment script will automatically detect and verify version compatibility
     - Supports various version formats including "package X.Y.Z" format
     - Provides detailed debug information for version detection and comparison
     
   **Automated Deployment Authentication**:
   
   This template uses the recommended Globus automated deployment approach with service credentials:
   
   - **Service Credentials**: Uses client ID and secret as service credentials via environment variables
   - **Environment Variables**: Sets `GCS_CLI_CLIENT_ID` and `GCS_CLI_CLIENT_SECRET` for authentication
   - **Non-Interactive Setup**: Enables fully automated deployment without user interaction
   - **Compatibility**: Works with both older and newer Globus Connect Server versions
   
   For details, see the [Globus Automated Deployment Documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)

3. S3 Storage:

   - Create S3 bucket or identify existing bucket
   - Note the bucket name

## Template Options

### Deployment Type

- **Integration**: Dynamic IP, suitable for testing
- **Production**: Includes Elastic IP, better for stable endpoints

### Authentication

- Using **Globus Auth** for identity federation 
- For details on Globus Auth, see the [official documentation](https://docs.globus.org/globus-connect-server/v5.4/admin-guide/identity-access-management/)

### CloudFormation Template Parameters

The template accepts the following parameters:

#### Required Parameters

- **VpcId**: VPC to deploy Globus Connect Server into
- **SubnetId**: Subnet within the selected VPC and Availability Zone
- **AvailabilityZone**: The Availability Zone to launch the instance in
- **KeyName**: Name of an existing AWS EC2 KeyPair to enable SSH access to the instance

#### Required Globus Parameters

Based on the [Globus endpoint setup CLI documentation](https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/#endpoint-setup):

- **GlobusOwner**: Identity username of the endpoint owner (e.g. user@example.edu)
  - This is a REQUIRED parameter with no default value
  - Must be a valid Globus identity that will own the endpoint
  - If not provided, the deployment will fail with a clear error message
  - Parameter is passed to the `--owner` option of the Globus setup command
- **GlobusContactEmail**: Email address for the support contact for this endpoint
  - This is a REQUIRED parameter that defaults to "admin@example.com"
  - Should be customized to a valid support email for your organization
  - Visible to users who need assistance with your endpoint
  - Parameter is passed to the `--contact-email` option of the Globus setup command
- **GlobusClientId/Secret**: Client credentials (required for GCS < 5.4.67, optional for newer versions)

#### Optional Parameters

- **ScriptUrl**: URL to the Globus installation script (defaults to GitHub repository)
- **DeploymentType**: "Integration" or "Production" (defaults to "Integration")
- **ForceElasticIP**: Force allocation of Elastic IP even for Integration deployment
- **InstanceType**: EC2 instance type (defaults to m6i.xlarge)
- **DefaultAdminIdentity**: Globus identity to be granted admin access
- **GlobusSubscriptionId**: Subscription ID to join this endpoint to your subscription
- **EnableS3Connector**: Enable S3 Connector (requires subscription)
- **S3BucketName**: Name of S3 bucket to connect (if S3 Connector is enabled)
- **GlobusDisplayName**: Display name for the Globus endpoint (defaults to "AWS GCS S3 Endpoint")
- **GlobusOrganization**: Organization name for the endpoint (defaults to "AWS")

#### Optional Globus Project Parameters (GCS 5.4.61+)

- **GlobusProjectId**: The Globus Auth project ID to register the endpoint in
- **GlobusProjectName**: Name for the Auth project if one needs to be created
- **GlobusProjectAdmin**: Admin username for the project if different from owner
- **GlobusAlwaysCreateProject**: Force creation of a new project even if one exists

For more information on Globus Connect Server options, see the [Globus CLI Reference Documentation](https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/).

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
  // === REQUIRED PARAMETERS ===
  
  // Required AWS parameters
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "your-key-pair"     // Name of an existing AWS EC2 KeyPair
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
  
  // Required Globus parameters - MUST be customized with valid values
  {
    "ParameterKey": "GlobusOwner",
    "ParameterValue": "user@example.com"  // CRITICAL: Identity username of the endpoint owner
                                          // Must be a valid Globus identity (no default value)
                                          // Cannot be a client ID or other non-identity value
                                          // Must be an actual Globus user identity that exists
  },
  {
    "ParameterKey": "GlobusContactEmail",
    "ParameterValue": "support@example.com"  // CRITICAL: Email address for endpoint support
                                             // Must be a valid email address
                                             // Cannot be a client ID or other non-email value
                                             // Visible to users who need assistance
  },
  {
    "ParameterKey": "GlobusClientId",     // Required for GCS < 5.4.67
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusClientSecret", // Required for GCS < 5.4.67
    "ParameterValue": "xxxxxxxxxxxxxxxxxxxx"
  },
  
  // === OPTIONAL PARAMETERS ===
  
  // Script and deployment options
  {
    "ParameterKey": "ScriptUrl",
    "ParameterValue": "https://raw.githubusercontent.com/scttfrdmn/globus-gcs-s3-deployment/main/scripts/globus-setup.sh"
  },
  {
    "ParameterKey": "DeploymentType",
    "ParameterValue": "Production"        // Optional: "Integration" or "Production"
  },
  {
    "ParameterKey": "InstanceType",
    "ParameterValue": "m6i.xlarge"        // Optional: EC2 instance type
  },
  
  // Optional Globus parameters
  {
    "ParameterKey": "DefaultAdminIdentity",
    "ParameterValue": "your-email@example.org"  // Optional: Admin identity
  },
  {
    "ParameterKey": "GlobusDisplayName",
    "ParameterValue": "Your Globus Endpoint"    // Optional: Defaults to "AWS GCS S3 Endpoint"
  },
  {
    "ParameterKey": "GlobusOrganization",
    "ParameterValue": "Your Organization Name"  // Optional: Defaults to "AWS"
  },
  
  // Optional Globus Project parameters (for GCS 5.4.61+)
  {
    "ParameterKey": "GlobusProjectId",         // Optional: Globus Auth project ID
    "ParameterValue": "12345678-abcd-1234-efgh-1234567890ab"
  },
  {
    "ParameterKey": "GlobusProjectName",       // Optional: Auth project name
    "ParameterValue": "My Globus Project"
  },
  
  // Optional connector parameters (requires subscription)
  {
    "ParameterKey": "GlobusSubscriptionId",    // Optional: Required for S3 connector
    "ParameterValue": "xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "EnableS3Connector",       // Optional: Defaults to "true"
    "ParameterValue": "true"
  },
  {
    "ParameterKey": "S3BucketName",            // Optional: Required if S3Connector is enabled
    "ParameterValue": "your-globus-bucket"
  }
]
```

> **Note**: The comments in the parameters file above are for documentation purposes only. Actual JSON files used with AWS CloudFormation cannot contain comments. Remove them before using this example.

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
cat /var/log/globus-setup.log              # Detailed Globus setup log

# Check environment variables for service credential authentication
env | grep GCS_CLI                         # Should show GCS_CLI_CLIENT_ID and GCS_CLI_CLIENT_SECRET

# You can also try to manually run the Globus setup script if needed
sudo bash /home/ubuntu/run-globus-setup.sh

# To skip duplicate endpoint checks:
sudo DEBUG_SKIP_DUPLICATE_CHECK=true bash /home/ubuntu/run-globus-setup.sh

# To run with explicit service credentials:
sudo GCS_CLI_CLIENT_ID=your_client_id GCS_CLI_CLIENT_SECRET=your_client_secret bash /home/ubuntu/run-globus-setup.sh

# To see detailed execution for debugging:
sudo bash -x /home/ubuntu/run-globus-setup.sh
```

The deployment script now includes:
- Detailed progress markers and validation steps
- Robust error handling that continues execution
- Multiple retry attempts for critical installation steps
- Comprehensive diagnostic information collection
- Version compatibility checks for different versions of Globus Connect Server
- Environment-based service credential authentication for automated deployment
- Non-interactive deployment using proper service authentication
- Checks for existing endpoints with the same name before deployment
- Ability to reuse existing endpoints rather than failing

## Authentication for Automated Deployment

The template now uses Globus Connect Server's recommended approach for automated deployment:

1. **Service Credentials**: 
   - Client ID and Secret are passed as environment variables
   - Uses `GCS_CLI_CLIENT_ID` and `GCS_CLI_CLIENT_SECRET` 
   - No manual interaction required during deployment

2. **Implementation Details**:
   - CloudFormation UserData sets environment variables
   - Deployment script uses these variables for authentication
   - Uses `--dont-set-advertised-owner` to prevent service identity showing as owner

3. **Troubleshooting Authentication Issues**:
   - Check `/var/log/globus-setup.log` for detailed authentication logs
   - Verify environment variables are set: `env | grep GCS_CLI`
   - Check [Globus authentication documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)
   - Review credentials in Globus Developer Console

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

## Version Compatibility Features

This template requires Globus Connect Server version 5.4.61 or higher. The script includes robust version detection and comparison features:

- **Intelligent Version Parsing**: Extracts version from various output formats
- **Package Version Identification**: Specifically handles the "package X.Y.Z" format
- **Proper SemVer Comparison**: Correctly compares major.minor.patch components
- **Detailed Version Diagnostics**: Provides comprehensive debug output for troubleshooting
- **Modern Command Format**: Uses the positional argument syntax required by newer Globus versions
- **API Evolution Support**: Handles parameter changes across versions:
  - For GCS < 5.4.67: Uses client credentials (--client-id, --client-secret)
  - For GCS 5.4.67+: Uses the updated API without client credentials
  - For GCS 5.4.61+: Supports project-related features (project-id, project-name, etc.)

The script specifically supports the common version format: `globus-connect-server, package 5.4.83, cli 1.0.58`, correctly extracting the package version for compatibility checks.

For more details on Globus Connect Server CLI options, see the [official CLI reference documentation](https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/#endpoint-setup).

## Globus Project Support

As of version 5.4.61+, Globus Connect Server supports organizing endpoints within projects:

- **Project ID**: The Globus Auth project ID where this endpoint will be registered
- **Project Name**: Name of the Auth project for the new endpoint client
- **Project Admin**: Globus username of the admin of the Auth project (if different from owner)
- **Always Create Project**: Forces creation of a new auth project even if you already have one

This template supports all project-related parameters, making it easy to organize endpoints within your Globus environment.

For more information on Globus Auth projects, see the [Globus Auth Management documentation](https://docs.globus.org/globus-connect-server/v5.4/admin-guide/identity-access-management/#auth_management).

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