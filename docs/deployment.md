# Deployment Steps for Globus Connect Server with S3 Connector

## Prerequisites

1. AWS Account and Permissions:

   - IAM permissions for CloudFormation, EC2, S3, IAM
   - EC2 key pair for SSH access
   - Existing VPC with public subnet (internet access required)

2. Globus Account and Registration:

   - Create account at [globus.org](https://www.globus.org/)
   - **IMPORTANT**: This template requires Globus Connect Server 5.4.61 or higher
     - The deployment script will automatically detect and verify version compatibility
   
   **CRITICAL PREREQUISITES FOR AUTOMATED DEPLOYMENT:**
   
   Follow these steps before launching the CloudFormation template:
   
   1. **Register Service Credentials:**
      - Go to [Globus Developer Console](https://app.globus.org/settings/developers)
      - Create a new project or use an existing one
      - Register a new application with:
        - Name: (choose a descriptive name, e.g., "GCS Automated Deployment")
        - Redirect URLs: (can be blank for service credentials)
        - Scopes: Select all relevant scopes
      - Record the **Client UUID** and **Client Secret** to use in your deployment
   
   2. **Create Project Administrator Role for Service Identity:**
      - Go to [Globus Auth Developer Console](https://auth.globus.org/v2/web/developers)
      - Select an existing project or create a new one
      - Select "Add" → "Add/remove admins"
      - Add your service identity in the "Add admin to project" field
        - Format: `YOUR_CLIENT_UUID@clients.auth.globus.org`
        - Example: `e0558739-6e6f-4600-a46d-983d309f88ff@clients.auth.globus.org`
      - Record the **Project ID** to use in your deployment
      
   3. **Prepare CloudFormation Parameters:**
      - Set `GlobusClientId` to your Client UUID
      - Set `GlobusClientSecret` to your Client Secret
      - Set `GlobusProjectId` to your Project ID
      - Set `GlobusOwner` to the identity that should own the endpoint
   
   If these steps are not completed before deployment, the endpoint setup will fail with authentication errors.
   
   See [Globus Automated Deployment Documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/) for complete details.
   
   **Automated Deployment Authentication:**
   
   The template uses service credentials with the following approach:
   
   - Uses client ID and secret for non-interactive authentication
   - Creates endpoint under the project administered by the service identity
   - By default, allows the advertised owner to be set for better visibility
   - Provides the `GlobusDontSetAdvertisedOwner` parameter for compatibility with environments where the `--dont-set-advertised-owner` flag is needed

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
  - The template uses `--dont-set-advertised-owner` to prevent showing the service identity as the owner
- **GlobusContactEmail**: Email address for the support contact for this endpoint
  - This is a REQUIRED parameter that defaults to "admin@example.com"
  - Should be customized to a valid support email for your organization
  - Visible to users who need assistance with your endpoint
  - Parameter is passed to the `--contact-email` option of the Globus setup command
- **GlobusClientId/Secret**: Service credentials required for automated deployment
  - Used by the template with environment variables for non-interactive authentication
  - These credentials must have permissions to create endpoints
  - Used with the recommended [automated deployment approach](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)

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
- **GlobusDontSetAdvertisedOwner**: Set to "true" to use the `--dont-set-advertised-owner` flag
  - Default: **false** (better visibility in Globus web interface)
  - When set to "true": Makes endpoint harder to find but may help with certain authentication issues
  - Only set to "true" if you encounter the error "Can not set the advertised owner when using client credentials"

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
    "ParameterKey": "GlobusClientId",     // Required for service credential authentication
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusClientSecret", // Required for service credential authentication
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
  {
    "ParameterKey": "GlobusDontSetAdvertisedOwner",  // Optional: Default false
    "ParameterValue": "false"                        // Set to "true" only if needed for authentication
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

## Advanced Configuration

### Debugging and Reliability Controls

The template includes configuration flags that control validation and error handling:

| Variable | Default | Purpose |
|----------|---------|---------|
| **DEBUG_SKIP_VERSION_CHECK** | false | Controls version compatibility checking |
| **DEBUG_SKIP_DUPLICATE_CHECK** | false | Controls endpoint duplication checking |
| **SHOULD_FAIL** | no | Controls CloudFormation stack failure behavior |

**When to modify these settings:**

- **DEBUG_SKIP_VERSION_CHECK**: Set to "true" only if your Globus version reports in an unusual format
- **DEBUG_SKIP_DUPLICATE_CHECK**: Set to "true" when testing endpoint creation or intentionally creating duplicates
- **SHOULD_FAIL**: Set to "yes" in production for strict validation; keep as "no" during testing

These variables can be modified in the CloudFormation template's UserData section or directly when running the helper script. When `SHOULD_FAIL="no"`, instances are retained with `DeletionPolicy: Retain` even if errors occur, facilitating troubleshooting.

## Troubleshooting

### Common Errors

1. **"Can not set the advertised owner when using client credentials"**: 
   - This error occurs in some environments when using client credentials
   - Cause: Some Globus service identity configurations require `--dont-set-advertised-owner`
   - Solution: Set the `GlobusDontSetAdvertisedOwner` parameter to "true" in your CloudFormation template

2. **Authentication Errors During Endpoint Setup**:
   - Error: "Failed to perform any Auth flows" or "Authentication/Authorization failed"
   - Cause: Missing Project Administrator Role for the service identity
   - Solution: Ensure you've completed the prerequisite steps:
     1. Register service credentials in Globus Developer Console
     2. Add the service identity as an admin to your project in Auth Developer Console
        (Format: `CLIENT_UUID@clients.auth.globus.org`)
     3. Use the correct Project ID in your CloudFormation parameters

3. **Finding Your Endpoint After Deployment**:
   - By default, the endpoint should appear under your account in the Globus web interface
   - If you set `GlobusDontSetAdvertisedOwner: true`, endpoints won't show up under your account
   - Solutions for finding endpoints with `GlobusDontSetAdvertisedOwner: true`:
     - Use the UUID from `/home/ubuntu/endpoint-uuid.txt` on the server
     - Search for your endpoint by its display name in Globus web interface
     - After deployment, use `globus-connect-server endpoint set-owner-string` to set the advertised owner

4. **"Credentials environment variables set: 0"**:
   - This indicates the environment variables for authentication aren't being set correctly
   - Solution: The script uses multiple authentication methods for maximum compatibility

If you see "WARNING - Failed to run module scripts-user" in the logs, this is likely a cloud-init warning that doesn't affect the deployment. Check these files for diagnostic information:

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

### Key Script Features

The deployment script includes:
- ✅ Robust error handling with detailed logging
- ✅ Version compatibility checks for Globus Connect Server
- ✅ Service credential authentication for non-interactive deployment
- ✅ Duplicate endpoint detection and reuse
- ✅ Automatic retry for critical installation steps

## Verification and Troubleshooting

### 1. Authentication for Automated Deployment

The template uses Globus Connect Server's recommended approach for automated deployment:

1. **Service Credentials**: 
   - Client ID and Secret are passed as environment variables (`GCS_CLI_CLIENT_ID`, `GCS_CLI_CLIENT_SECRET`)
   - No manual interaction required during deployment

2. **Troubleshooting Authentication Issues**:
   - Check `/var/log/globus-setup.log` for detailed authentication logs
   - Verify environment variables are set: `env | grep GCS_CLI`
   - Check [Globus documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)

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

### 4. Set Advertised Owner (if using client credentials)

When deploying with service credentials, the endpoint is created with the `--dont-set-advertised-owner` flag, which makes it difficult to find in the Globus web interface. After deployment, you can set the advertised owner to make it more visible:

```bash
# Get the endpoint UUID
ENDPOINT_UUID=$(cat /home/ubuntu/endpoint-uuid.txt)

# Set the advertised owner to your Globus identity
globus-connect-server endpoint set-owner-string "your-email@example.com"

# Verify the change
globus-connect-server endpoint show
```

This makes the endpoint appear under your account in the Globus web interface.

### 5. Verify access policies

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