# Globus Connect Server with S3 Connector on AWS

This repository contains a CloudFormation template for deploying Globus Connect Server with Amazon S3 storage integration. This solution enables high-performance data transfers between S3 buckets and other Globus endpoints.

## Features

- **AWS CloudFormation Template**: Infrastructure-as-code deployment
- **S3 Integration**: Connect to S3 storage directly using instance credentials
- **Security**: IAM roles and policies for secure access
- **Globus Auth Integration**: Identity federation using Globus Auth
- **Automated Authentication**: Uses environment-based service credentials for non-interactive deployment
- **Automatic Collection Creation**: Collections are automatically created during deployment
- **Production & Testing Modes**: Configurable deployment types
- **Optimized Deployment**: Streamlined UserData script stays within AWS limits
- **Multi-word Parameters**: Support for spaces in organization and display names
- **Version Validation**: Ensures compatibility with Globus Connect Server 5.4.61+
- **Simplified Parameters**: Reduced parameter set for easier deployment

## Prerequisites

1. **AWS Account and Permissions**:
   - IAM permissions for CloudFormation, EC2, S3, IAM
   - Existing EC2 key pair in your AWS account for SSH access
   - Existing VPC with public subnet

2. **Globus Account and Registration**:
   - Account at [globus.org](https://www.globus.org/)
   - Application registered in [Globus Developer Console](https://developers.globus.org/)
   - **Service credentials** (Client ID and Client Secret) REQUIRED for automated deployment
     - These credentials are used with environment variables for non-interactive authentication
     - Must have permissions to create endpoints in Globus
     - Used with the recommended [automated deployment approach](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)
   - **Owner identity username** (e.g., user@example.edu) - CRITICAL REQUIRED PARAMETER
     - This must be a valid Globus identity that will own the endpoint
     - Must be an actual Globus user identity that exists (cannot be a client ID)
     - The template parameter `GlobusOwner` has no default value and must be set
     - Deployment will fail if this is not a valid Globus identity
   - **Base name** for consistent naming - CRITICAL REQUIRED PARAMETER
     - The template parameter `GlobusBaseName` has no default value and must be set
     - Used for naming the endpoint and collections consistently
   - **Contact email** for support requests - CRITICAL REQUIRED PARAMETER
     - Must be a valid email address (cannot be a client ID)
     - Email visible to users who need assistance with your endpoint
     - The template parameter `GlobusContactEmail` defaults to "admin@example.com" but should be customized
   - **Subscription ID** - REQUIRED FOR S3 CONNECTOR
     - Must be a valid Globus subscription ID (e.g., "DEFAULT" or specific ID)
     - ⚠️ **CRITICAL PERMISSION REQUIREMENT**:
       1. The GlobusOwner identity MUST have subscription manager role, OR
       2. The endpoint must be registered in a project created by a subscription manager
     - Without proper subscription permissions, S3 connector features will not work
     - The template parameter `GlobusSubscriptionId` must be set for S3 connector
   - **IMPORTANT**: Requires Globus Connect Server 5.4.61 or higher (template will verify version)

## Documentation

The repository includes detailed documentation on deploying and using Globus Connect Server with S3:

- [Quick Start Guide](./docs/quickstart.md) - Concise steps for deployment (start here!)
- [Deployment Guide](./docs/deployment.md) - Comprehensive instructions for deploying the solution
- [CLI Operations](./docs/cli-operations.md) - How to use the Globus CLI for file transfers
- [Globus Groups](./docs/groups.md) - Managing access through Globus Groups
- [Collection Types](./docs/collections.md) - Understanding Globus collections and S3 integration

## Getting Started

Review the [Quick Start Guide](./docs/quickstart.md) for a concise overview of the setup process.

### Prerequisites

Before deploying, make sure you have:

1. Completed the [AWS Account and Permissions](#prerequisites) setup
2. Completed the [Globus Service Account Setup](./docs/prerequisites.md) process - **CRITICAL**
3. Gathered all required parameters (GlobusBaseName, GlobusOwner, etc.)

> **IMPORTANT**: The [Prerequisites Guide](./docs/prerequisites.md) contains detailed instructions for setting up the Globus service account, obtaining necessary credentials, and configuring required permissions. These steps are **mandatory** for successfully deploying the template.

### Deployment Options

#### Option 1: CloudFormation Console

> **Note:** Quick Launch buttons have been temporarily removed while the template is being updated.
> Please use the AWS CLI deployment method (Option 2) below.

To deploy using the CloudFormation console:

1. Open the AWS CloudFormation console in your desired region
2. Choose "Create stack" > "With new resources (standard)"
3. Select "Upload a template file" and upload the `globus-gcs-s3-template.yaml` file
4. Follow the prompts to fill in the parameters and create the stack

* Be sure to check the "I acknowledge that AWS CloudFormation might create IAM resources" checkbox in the console.
* Fill in all required parameters with your specific values.

#### Option 2: AWS CLI

1. Clone this repository:
   ```
   git clone https://github.com/scttfrdmn/globus-gcs-s3-deployment.git
   ```

2. Review the [Quick Start Guide](./docs/quickstart.md) and [deployment documentation](./docs/deployment.md).

3. Deploy using CloudFormation:
   ```bash
   # Create the stack
   aws cloudformation create-stack \
     --stack-name globus-gcs \
     --template-body file://globus-gcs-s3-template.yaml \
     --parameters file://parameters.json \
     --capabilities CAPABILITY_IAM
   
   # Monitor deployment status
   aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus" --output text
   
   # Or wait for completion
   aws cloudformation wait stack-create-complete --stack-name globus-gcs
   ```

   Note: Boolean parameters in the template must be specified as strings:
   ```json
   {
     "ParameterKey": "RemoveServiceAccountRole",
     "ParameterValue": "true"
   }
   ```

## Deployment Features

The CloudFormation template includes the following reliability features:

- **Cloud-Init Compatible**: Robust script design that works reliably with cloud-init
- **Progressive Execution**: Continues deployment despite non-critical errors
- **Detailed Progress Tracking**: Step-by-step progress markers for easier troubleshooting
- **Installation Retries**: Automatic retry mechanisms for critical installation steps
- **Comprehensive Diagnostics**: Detailed logs and validation files for troubleshooting
- **Robust Error Handling**: Comprehensive error handling in all deployment steps
- **Resource Signaling**: Proper CloudFormation resource signaling with timeouts
- **IAM Permission Controls**: Appropriate IAM permissions for all operations
- **Deployment Logs**: Detailed logging for troubleshooting
- **Admin Setup Retries**: Automatic retry logic for key configuration steps
- **Deployment Summary**: Generates a deployment summary file on the instance for quick reference
- **Automatic Collection Creation**: Automatically creates collections for the S3 gateway
- **Troubleshooting Mode**: Keeps instances running even when Globus setup fails for easier troubleshooting
- **Diagnostic Scripts**: Creates diagnostic and manual setup scripts to help resolve issues
- **Version Compatibility**: Handles different Globus Connect Server versions automatically
- **Optimized UserData**: Streamlined script that stays well below CloudFormation's 16KB encoded limit

## Platform Configuration

The template deploys Globus Connect Server with the following configuration:

1. **Operating System**: Ubuntu Server 22.04 LTS
2. **Authentication**: Uses Globus Auth for identity federation
3. **Storage**: Connects to Amazon S3 using instance credentials
4. **Networking**: The template ensures the Globus Connect Server is publicly accessible through one of two approaches:
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
- Globus-specific logs: `/var/log/globus-setup.log` and `/home/ubuntu/globus-setup-complete.log`

## Troubleshooting

If Globus setup fails, the instance will still be created and kept running for troubleshooting. You'll find these diagnostic resources on the instance:

1. **Deployment Debug Log**: `/home/ubuntu/cloud-init-debug.log` - Detailed step-by-step installation progress
2. **Cloud-Init Module Issues**: `/home/ubuntu/cloud-init-modules.log` - Information about script-user module issues
3. **Manual Setup Script**: `/home/ubuntu/run-globus-setup.sh` - Allows you to manually attempt the Globus setup
4. **Status File**: `/home/ubuntu/globus-setup-failed.txt` - Contains failure information if setup failed
5. **Deployment Summary**: `/home/ubuntu/deployment-summary.txt` - Shows the overall deployment status and configuration
6. **Complete Logs**: `/home/ubuntu/globus-setup-complete.log` - Contains the full setup log
7. **Deployment Errors**: `/home/ubuntu/deployment-error.txt` - Contains any deployment error details
8. **User Data Log**: `/var/log/user-data.log` - Complete deployment script execution log
9. **Cloud-Init Output**: `/var/log/cloud-init-output.log` - Standard cloud-init output

### Common Issues

#### Version Compatibility

This template requires Globus Connect Server version 5.4.61 or higher. The script includes robust version detection and comparison features:

- **Intelligent Version Parsing**: Extracts version from various output formats
- **Package Version Identification**: Specifically handles the "package X.Y.Z" format
- **Proper SemVer Comparison**: Correctly compares major.minor.patch components
- **Detailed Version Diagnostics**: Provides comprehensive debug output for troubleshooting
- **Modern Command Format**: Uses the positional argument syntax required by newer Globus versions
- **API Evolution Support**: Handles parameter changes across different Globus Connect Server versions

The script specifically supports the common version format: `globus-connect-server, package 5.4.83, cli 1.0.58`, correctly extracting the package version for compatibility checks.

#### Multi-word Parameter Values

The template supports multi-word values for parameters like `GlobusOrganization` and `GlobusDisplayName`:

- **Proper Quoting**: All parameters are properly quoted in command execution
- **Standard Parameter Format**: Both single-word and multi-word values work correctly
- Example: "Amazon Web Services" and "My Globus Endpoint" are properly handled

#### Installation Process for Ubuntu

The template follows the official Globus Connect Server installation process for Ubuntu:

1. **Repository Setup**: Downloads and installs the official Globus repository package, which handles all required configuration.

2. **Package Installation**: Installs the specific `globus-connect-server54` package as recommended in the official documentation.

3. **Detailed Error Handling**: Includes comprehensive error handling at each step with clear error messages and diagnostic information.

This approach follows best practices from the official Globus documentation to ensure compatibility and reliability when installing on Ubuntu systems. The installation process properly handles the repository setup, eliminating URL format issues or missing GPG keys.

### Debugging Environment Variables

The template supports special debugging environment variables that can help resolve complex deployment issues:

- **DEBUG_SKIP_VERSION_CHECK**: When set to "true", bypasses the version compatibility check. Useful when testing with versions that report themselves differently but are compatible.

- **DEBUG_SKIP_DUPLICATE_CHECK**: When set to "true", skips duplicate endpoint checking. Useful if you suspect the endpoint check is causing issues or you want to create a new endpoint with the same name for testing.

These variables can be modified in the CloudFormation template's UserData section for troubleshooting purposes.

### Automated Authentication

The template uses Globus Connect Server's recommended approach for automated deployment:

- **Service Credentials**: Uses environment variables for authentication (`GCS_CLI_CLIENT_ID` and `GCS_CLI_CLIENT_SECRET`)
- **Non-Interactive**: Allows fully automated deployment without user interaction
- **Compatibility**: Works with both older and newer versions of Globus Connect Server
- **Documentation**: Follows best practices from [Globus Automated Deployment Documentation](https://docs.globus.org/globus-connect-server/v5/automated-deployment/)

### Common Troubleshooting Steps

1. SSH to the instance: `ssh -i /path/to/your/key.pem ubuntu@<PUBLIC-IP-ADDRESS>`
2. Check setup status: `cat /home/ubuntu/globus-setup-failed.txt`
3. Check authentication variables: `env | grep GCS_CLI`
4. Run manual setup with service credential authentication: 
   ```bash
   # Using credential files and environment-based authentication:
   CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
   CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
   DISPLAY_NAME=$(cat /home/ubuntu/globus-display-name.txt)
   OWNER=$(cat /home/ubuntu/globus-owner.txt)
   EMAIL=$(cat /home/ubuntu/globus-contact-email.txt)
   
   # Set environment variables for service credential authentication
   export GCS_CLI_CLIENT_ID="$CLIENT_ID"
   export GCS_CLI_CLIENT_SECRET="$CLIENT_SECRET"
   
   # CRITICAL: Must provide valid owner and contact email values
   bash /home/ubuntu/run-globus-setup.sh "$CLIENT_ID" "$CLIENT_SECRET" "$DISPLAY_NAME" "Organization Name" "$OWNER" "$EMAIL"
   
   # Or if you have credentials directly:
   export GCS_CLI_CLIENT_ID="your-client-id"
   export GCS_CLI_CLIENT_SECRET="your-client-secret"
   bash /home/ubuntu/run-globus-setup.sh "your-client-id" "your-client-secret" "display-name" "organization-name" "user@example.edu" "contact@example.edu"
   ```
5. Check logs: `cat /home/ubuntu/globus-setup-complete.log` and `cat /var/log/globus-setup.log`
6. If endpoint creation still fails, try running the setup with debug output:
   ```bash
   # Run with debug output
   bash -x /home/ubuntu/run-globus-setup.sh "$CLIENT_ID" "$CLIENT_SECRET" "$DISPLAY_NAME" "Organization Name" "$OWNER" "$EMAIL"
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.