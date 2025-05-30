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
      - **REQUIRED**: Set `GlobusProjectId` to your Project ID (from step ii)
        - This is required for automated deployments with service credentials
        - You MUST provide this when a service identity has access to multiple projects
        - Without this parameter, deployment will fail with "You have multiple existing projects" error
      - Set `GlobusOwner` to the identity that should own the endpoint
        - For fully automated deployments, this can be the service identity itself
        - Format: `CLIENT_UUID@clients.auth.globus.org`
        - Example: `e0558739-6e6f-4600-a46d-983d309f88ff@clients.auth.globus.org`
   
   If these steps are not completed before deployment, the endpoint setup will fail with authentication errors.
   
   See [Globus Automated Deployment Documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/) for complete details.
   
   **Automated Deployment Authentication:**
   
   The template uses service credentials with the following approach:
   
   - Uses client ID and secret for non-interactive authentication
   - Creates endpoint under the project administered by the service identity
   - Always uses the `--dont-set-advertised-owner` flag for reliable authentication with service credentials
   - Automatically resets the endpoint owner after creation for better visibility (controlled by the `ResetEndpointOwner` parameter)
   - Allows customizing which identity appears as the owner (using the `EndpointResetOwnerTarget` parameter)

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

- **GlobusDisplayName**: Display name for the Globus endpoint
  - This is a REQUIRED parameter with no default value
  - Must be unique across your endpoints to avoid conflicts
  - Used to identify your endpoint in the Globus web interface
  - This is the name that appears in search results
- **GlobusOrganization**: Organization name for the Globus endpoint
  - This is a REQUIRED parameter with no default value
  - Visible to all users who access your endpoint
  - Used to identify which organization owns or operates the endpoint
  - Appears in endpoint details and search results
- **GlobusOwner**: Identity username of the endpoint owner (e.g. user@example.edu)
  - This is a REQUIRED parameter with no default value
  - Must be a valid Globus identity that will own the endpoint
  - If not provided, the deployment will fail with a clear error message
  - Parameter is passed to the `--owner` option of the Globus setup command
  - The template uses `--dont-set-advertised-owner` for reliable authentication with service credentials
  - By default, this identity is also used as the advertised owner after endpoint creation
  - This behavior can be customized with the `ResetEndpointOwner` and `EndpointResetOwnerTarget` parameters
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
#### Required S3 Connector Parameters

- **GlobusSubscriptionId**: Subscription ID to join this endpoint to your subscription (REQUIRED for S3 connector)
  - Your organization must have a Globus subscription
  - You can use "DEFAULT" to use your organization's default subscription
  - Or provide a specific subscription ID
  - ⚠️ **CRITICAL PERMISSION REQUIREMENT**: The GlobusOwner identity (or service identity) MUST either:
    1. Have subscription manager role for the specified subscription, OR
    2. Be part of a project created by someone with subscription manager rights
  - **IMPORTANT**: This is the most common deployment failure point for S3 connector
  - Symptoms of permission issues:
    - Deployment succeeds but S3 connector features don't work
    - `/home/ubuntu/SUBSCRIPTION_WARNING.txt` file is created during deployment
    - Error messages about failing to set subscription ID
  - How to fix after deployment if S3 connector fails:
    1. Have a subscription manager log in to the endpoint with SSH
    2. Run: `globus-connect-server endpoint set-subscription-id DEFAULT`
    3. Or have them set it via the Globus web interface under endpoint settings
  - Without proper subscription management, premium features like S3 connector won't work at all
- **S3BucketName**: Name of S3 bucket to connect (required when S3 Connector is enabled)

#### Optional S3 Connector Parameters

- **EnableS3Connector**: Whether to enable S3 Connector (defaults to true for this template)

#### Required Globus Project Parameters (GCS 5.4.61+)

- **GlobusProjectId**: The Globus Auth project ID to register the endpoint in
  - This is REQUIRED for automated deployments with service credentials
  - Ensures the endpoint is registered in the correct project
  - Required when a service identity has access to multiple projects
  - Must be obtained from the Globus Auth Developer Console
- **GlobusProjectName**: Name for the Auth project if one needs to be created
- **GlobusProjectAdmin**: Admin username for the project if different from owner
- **GlobusAlwaysCreateProject**: Force creation of a new project even if one exists

#### Endpoint Owner Visibility Parameters

- **ResetEndpointOwner**: Reset the endpoint's advertised owner after setup for better visibility
  - Default: **true** (automatically resets owner after deployment)
  - When set to "false": Keeps the endpoint under the service identity (less visible)
  - This allows the endpoint to be properly visible in the Globus web interface
  - Runs automatically after successful endpoint creation
- **EndpointResetOwnerTarget**: Which identity to set as the advertised owner
  - Default: **GlobusOwner** (uses the value from GlobusOwner parameter)
  - Options: "GlobusOwner", "DefaultAdminIdentity", or "GlobusContactEmail"
  - Controls which identity appears as the owner in the Globus web interface

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
    "ParameterKey": "GlobusClientId", // Client UUID from service credential registration
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusClientSecret", // Secret from service credential registration
    "ParameterValue": "xxxxxxxxxxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusProjectId", // CRITICAL: Project ID from step 2
    "ParameterValue": "12345678-abcd-1234-efgh-1234567890ab"
  },
  {
    "ParameterKey": "GlobusOwner",
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@clients.auth.globus.org"  // CRITICAL: For automated deployment
                                          // Must be either:
                                          // 1. The service identity (CLIENT_UUID@clients.auth.globus.org), or
                                          // 2. A valid Globus identity (user@example.com)
  },
  {
    "ParameterKey": "GlobusContactEmail",
    "ParameterValue": "support@example.com"  // CRITICAL: Email address for endpoint support
                                             // Must be a valid email address
                                             // Visible to users who need assistance
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
    "ParameterValue": "Your Globus Endpoint"    // REQUIRED: Must be unique across your endpoints
  },
  {
    "ParameterKey": "GlobusOrganization",
    "ParameterValue": "Your Organization Name"  // REQUIRED: Visible to all users
  },
  
  // Required Globus Project parameters (for GCS 5.4.61+)
  {
    "ParameterKey": "GlobusProjectId",         // REQUIRED: Globus Auth project ID
    "ParameterValue": "12345678-abcd-1234-efgh-1234567890ab"
  },
  {
    "ParameterKey": "GlobusProjectName",       // Optional: Auth project name
    "ParameterValue": "My Globus Project"
  },
  {
    "ParameterKey": "ResetEndpointOwner",          // Optional: Default "true"
    "ParameterValue": "true"                       // Set to "false" to keep service identity as owner
  },
  {
    "ParameterKey": "EndpointResetOwnerTarget",    // Optional: Default "GlobusOwner"
    "ParameterValue": "GlobusOwner"                // Options: "GlobusOwner", "DefaultAdminIdentity", "GlobusContactEmail"
  },
  
  // Optional connector parameters (requires subscription)
  // === REQUIRED S3 CONNECTOR PARAMETERS ===
  
  {
    "ParameterKey": "GlobusSubscriptionId",    // REQUIRED: Subscription ID for S3 connector
    "ParameterValue": "xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "S3BucketName",            // REQUIRED: Bucket for S3 connector
    "ParameterValue": "your-globus-bucket"
  },
  
  // === OPTIONAL S3 CONNECTOR PARAMETERS ===
  
  {
    "ParameterKey": "EnableS3Connector",       // Optional: Defaults to "true" in this template
    "ParameterValue": "true"
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

### AMI Selection

The template uses AWS Systems Manager Parameter Store to automatically select the latest Ubuntu 22.04 LTS AMI for your region, ensuring you get the most secure and up-to-date base image without manual updates. (Hat tip to Luke Coady for this improvement!)

### Common Errors

1. **"Can not set the advertised owner when using client credentials"**: 
   - This error occurs in some environments when using client credentials
   - Cause: Some Globus service identity configurations require `--dont-set-advertised-owner`
   - Solution: Set the `GlobusDontSetAdvertisedOwner` parameter to "true" in your CloudFormation template

2. **Authentication Errors During Endpoint Setup**:
   - Error: "Failed to perform any Auth flows" or "Authentication/Authorization failed"
   - Causes and Solutions:
     1. **Missing Project ID**: The `GlobusProjectId` parameter is not set or incorrect
        - Solution: Set the correct Project ID in your CloudFormation parameters
     2. **Missing Project Administrator Role**: Service identity not added as admin
        - Solution: Add the service identity as an admin to your project in Auth Developer Console
          (Format: `CLIENT_UUID@clients.auth.globus.org`)
     3. **Incorrect Owner**: The owner identity is not properly formatted
        - Solution: Set `GlobusOwner` to the service identity (for fully automated deployments)
          (Format: `CLIENT_UUID@clients.auth.globus.org`)

3. **Finding Your Endpoint After Deployment**:
   - By default, the endpoint will appear under your account in the Globus web interface
   - The deployment automatically uses the `--dont-set-advertised-owner` flag for service credentials
   - Immediately after creation, the endpoint will reset its advertised owner based on your parameters:
     - Default: Sets the advertised owner to the value from `GlobusOwner` parameter
     - Configurable using `EndpointResetOwnerTarget` to use another identity
   - To change this behavior:
     - Set `ResetEndpointOwner: false` to keep the service identity as owner (less visible)
     - Customize `EndpointResetOwnerTarget` to control which identity is shown as the owner
   - If you can't find your endpoint:
     - Use the UUID from `/home/ubuntu/endpoint-uuid.txt` on the server
     - Search for your endpoint by its display name in Globus web interface
     - Manually run `globus-connect-server endpoint set-owner-string "your-email@example.com"` on the server

4. **"Credentials environment variables set: 0"**:
   - This indicates the environment variables for authentication aren't being set correctly
   - Solution: The script uses multiple authentication methods for maximum compatibility

5. **Subscription Association Fails / S3 Connector Doesn't Work**:
   - Error: "Failed to set subscription ID" or S3 connector features don't work
   - Causes and Solutions:
     1. **Missing Subscription Manager Role**: The GlobusOwner identity doesn't have subscription manager permissions
        - Solution: Update the `GlobusOwner` parameter to an identity with subscription manager role
        - Alternative: Have a subscription manager set the subscription ID after deployment
     2. **Project Not Created by Subscription Manager**: The project used wasn't created by a subscription manager
        - Solution: Create a new project where the creator has subscription manager role
     3. **Missing Project Setup**: Proper project configuration is required for subscription association
        - Solution: Ensure both `GlobusProjectId` and `GlobusOwner` parameters are set correctly
   - How to fix after deployment:
     - Look for the file `/home/ubuntu/SUBSCRIPTION_WARNING.txt` with detailed guidance
     - Have a subscription manager run: `globus-connect-server endpoint set-subscription-id DEFAULT`
     - Or have them set it via the Globus web interface under endpoint settings

6. **Script Syntax Errors**:
   - Error: "Bootstrap script failed at line XX with exit code 2" or "syntax error near unexpected token 'fi'"
   - Causes and Solutions:
     1. **Mismatched If/Fi Statements**: The script contains unbalanced if/fi constructs
        - Solution: Check script with `bash -n /home/ubuntu/globus-setup.sh` before running
        - Fix: Use simpler control structures and avoid deeply nested conditionals
     2. **Heredoc Issues**: Heredocs within complex if/else blocks can cause syntax problems
        - Solution: Replace heredocs with multiple echo statements in complex sections
        - Example: `echo "line1" > file.txt; echo "line2" >> file.txt` instead of heredoc
     3. **Complex Conditional Structures**: Deeply nested if/else/fi structures are error-prone
        - Solution: Simplify logic or use functions to break up complex sections
   - How to fix:
     - Use `bash -n scriptname.sh` to validate scripts before running them
     - The latest version of the script includes self-validation and improved error handling

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

### 4. Verify Endpoint Owner Settings

The template automatically handles endpoint owner visibility through the endpoint reset feature. You can verify the configured settings:

```bash
# View the deployment summary to see owner reset status
cat /home/ubuntu/deployment-summary.txt

# Check the specific owner reset results
cat /home/ubuntu/endpoint-reset-owner.txt

# Verify the current endpoint settings
globus-connect-server endpoint show
```

If needed, you can manually change the advertised owner:

```bash
# Set the advertised owner to another identity
globus-connect-server endpoint set-owner-string "your-email@example.com"

# Verify the change
globus-connect-server endpoint show
```

By default (`ResetEndpointOwner: true`), the endpoint should appear under your account in the Globus web interface based on the `EndpointResetOwnerTarget` parameter.

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

When you delete the CloudFormation stack, the EC2 instance is retained by default (using `DeletionPolicy: Retain`). This is by design to prevent accidental deletion of Globus resources. 

**IMPORTANT**: You must first clean up the Globus endpoint resources before deleting the CloudFormation stack, or the deletion may fail due to dependent resources. The stack provides a helper script that simplifies this process.

### Using the Teardown Script (Recommended)

1. SSH into the instance:
   ```bash
   # Get the public address
   PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
     --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)
   
   # Connect via SSH
   ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS
   ```

2. Run the teardown script:
   ```bash
   # Execute the teardown script
   bash /home/ubuntu/teardown-globus.sh
   ```

   This script will:
   - Delete all collections
   - Remove all storage gateways
   - Delete the endpoint registration from Globus
   - Stop Globus services
   - Create a marker file indicating successful teardown

3. After successful teardown, exit the instance and delete the CloudFormation stack:
   ```bash
   aws cloudformation delete-stack --stack-name globus-gcs
   ```

### Manual Teardown (Alternative)

If the teardown script isn't available or encounters issues, you can manually clean up the Globus resources:

```bash
# SSH into the instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Source environment variables for proper credentials
source /home/ubuntu/setup-env.sh

# List and delete all collections
echo "Deleting collections..."
globus-connect-server collection list
COLLECTIONS=$(globus-connect-server collection list 2>/dev/null | grep -v "^ID" | awk '{print $1}')
for collection in $COLLECTIONS; do
  echo "Deleting collection: $collection"
  globus-connect-server collection delete "$collection"
done

# List and delete all storage gateways
echo "Deleting storage gateways..."
globus-connect-server storage-gateway list
GATEWAYS=$(globus-connect-server storage-gateway list 2>/dev/null | grep -v "^ID" | awk '{print $1}')
for gateway in $GATEWAYS; do
  echo "Deleting gateway: $gateway"
  globus-connect-server storage-gateway delete "$gateway"
done

# Get the endpoint ID
ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt || globus-connect-server endpoint show | grep -E 'UUID|ID' | awk '{print $2}' | head -1)

# Delete the endpoint from Globus
[ -n "$ENDPOINT_ID" ] && globus-connect-server endpoint delete

# Verify the endpoint was deleted
globus-connect-server endpoint show
```

### Troubleshooting Stack Deletion

If CloudFormation stack deletion fails:

1. Check which resources are causing the failure:
   ```bash
   aws cloudformation describe-stack-events --stack-name globus-gcs \
     --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].{Resource:LogicalResourceId,Reason:ResourceStatusReason}" \
     --output table
   ```

2. Common issues:
   - **Security Group Deletion Failure**: Indicates the EC2 instance is still running
     - Solution: Manually terminate the EC2 instance first
   - **IAM Role Deletion Failure**: May indicate permissions issues
     - Solution: Check for resources still using the role

3. If the EC2 instance needs to be manually terminated:
   ```bash
   # Get instance ID
   INSTANCE_ID=$(aws ec2 describe-stacks --stack-name globus-gcs \
     --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)
   
   # Terminate the instance
   aws ec2 terminate-instances --instance-ids $INSTANCE_ID
   ```

4. After resolving the specific issues, retry the stack deletion:
   ```bash
   aws cloudformation delete-stack --stack-name globus-gcs
   ```

The teardown process ensures that all Globus resources are properly removed from Globus's systems before the CloudFormation resources are deleted, preventing orphaned resources and failed deletions.

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