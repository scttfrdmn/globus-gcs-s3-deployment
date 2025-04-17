# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- CloudFormation validation: `aws cloudformation validate-template --template-body file://globus-gcs-s3-template.yaml`
- CloudFormation linting: `cfn-lint globus-gcs-s3-template.yaml`
- YAML linting: `yamllint globus-gcs-s3-template.yaml`
- Markdown linting: `markdownlint README.md docs/*.md`
- CloudFormation deployment check: `aws cloudformation describe-stack-events --stack-name globus-gcs | grep -A 2 "FAILED"`

## Ubuntu Package Information

The deployment uses Ubuntu 22.04 LTS and installs Globus packages using the Debian/Ubuntu package manager. Key details:

- The official Globus Connect Server repository is added to APT sources
- Package install path: `/usr/share/globus-connect-server/`
- Configuration path: `/etc/globus-connect-server/`
- Service names vary by installation and may include:
  - `globus-gridftp-server.service`
  - Other related services
- Command structure:
  - Main command: `globus-connect-server`
  - Version checking: `globus-connect-server --version` (returns "globus-connect-server, package X.Y.Z, cli A.B.C")
  - Endpoint setup (v5.4.61+): `globus-connect-server endpoint setup [OPTIONS] DISPLAY_NAME`
    - Required parameters:
      - `--organization`: Organization that owns this endpoint
      - `--contact-email`: Email address of the support contact
      - `--owner`: Identity username of the owner
    - Optional parameters:
      - `--project-id`: The Globus Auth project ID (new in 5.4.61)
      - `--project-name`: Name of the Auth project (new in 5.4.72)
      - `--project-admin`: Globus username of the admin (new in 5.4.62)
      - `--always-create-project`: Create a new project even if admin has one
    - Standard options:
      - `--agree-to-letsencrypt-tos`: Agree to Let's Encrypt TOS
    - Version-specific parameters:
      - For GCS < 5.4.67: `--client-id`, `--client-secret`
      - For GCS >= 5.4.67: Client credentials not needed
    - Display name is a positional argument (last argument)
  - Create permissions: `globus-connect-server endpoint permission create`
  - Create storage gateway: `globus-connect-server storage-gateway create s3 [OPTIONS]`
    - S3 is a subcommand (positional argument)
  - Show endpoint: `globus-connect-server endpoint show`
  - Collection management:
    - List collections: `globus-connect-server collection list`
    - Create collection: `globus-connect-server collection create --storage-gateway <ID> --display-name "Name"`
    - Delete collection: `globus-connect-server collection delete <ID>`
    - Set permissions: `globus-connect-server endpoint permission create --identity <EMAIL> --permissions rw --collection <ID>`
  - Endpoint removal: `globus-connect-server endpoint remove`
  - **VERSION COMPATIBILITY**:
    - Template requires Globus Connect Server 5.4.61+
    - The script handles various version output formats
    - Specifically extracts version from "package X.Y.Z" format
    - Performs proper SemVer comparison for compatibility checks
    - Handles parameter changes across different versions
    - Documentation: https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/
- For command path issues:
  - Verify installation: `dpkg -l | grep globus`
  - Check command path: `which globus-connect-server`
  - List available commands: `find /usr/bin -name "*globus*"`

## Helper Scripts

The deployment includes several helper scripts to assist with management and troubleshooting:

- **setup-env.sh**: Sets up Globus environment variables for manual operations
  - Sources variables from files in `/home/ubuntu/`
  - Creates a sourceable exports file at `/home/ubuntu/globus-env-exports.sh`
  - Usage: `source /home/ubuntu/globus-env-exports.sh` to persist variables in your shell

- **create-collection.sh**: Helps create and manage collections
  - Supports listing gateways, creating collections, and setting permissions
  - Usage: `./create-collection.sh --help` to see all options
  - Example: `./create-collection.sh --create-collection <gateway-id> "My Collection"`

- **teardown-globus.sh**: Properly removes Globus resources before stack deletion
  - Removes collections, storage gateways, and endpoint registration
  - Should be run before attempting to delete the CloudFormation stack
  - Usage: `bash /home/ubuntu/teardown-globus.sh`
  - **IMPORTANT**: Must be run before stack deletion to avoid resource deletion failures

- **collect-diagnostics.sh**: Collects diagnostic information for troubleshooting
  - Gathers logs, configuration, and system status for debugging
  - Usage: `bash /home/ubuntu/collect-diagnostics.sh`

## Collection Management

The deployment uses a manual collection creation approach to provide greater flexibility:

1. **Storage Gateway Creation**: Automated during deployment
   - S3 gateway is created automatically if enabled
   - POSIX gateway is created automatically if enabled
   
2. **Collection Creation**: Manual post-deployment step (one of two methods)
   - Option 1: Use the Globus web UI (app.globus.org)
     1. Log in to the Globus web UI
     2. Navigate to the Endpoints tab
     3. Find and select your endpoint by name or UUID
     4. Go to the Collections tab
     5. Click "Add a Collection" and follow the prompts
   
   - Option 2: Use the create-collection.sh helper script
     1. List available gateways: `./create-collection.sh --list-gateways`
     2. Create a collection: `./create-collection.sh --create-collection <gateway-id> "My Collection"`
     3. List collections: `./create-collection.sh --show-collections`
     4. Set permissions: `./create-collection.sh --permissions <collection-id> user@example.edu`

3. **S3 Collection Requirements**:
   - S3 gateway requires AWS credentials for collection creation
   - Web UI provides an easier interface for entering these credentials
   - When using the script, you still need to authenticate with AWS

This manual approach avoids deployment failures due to auth issues and provides more flexibility in collection configuration.

## Teardown Process

When deleting the CloudFormation stack, follow this sequence to avoid deletion failures:

1. SSH into the instance: `ssh -i key.pem ubuntu@instance-ip`
2. Run the teardown script: `bash /home/ubuntu/teardown-globus.sh`
3. Verify that all Globus resources were removed successfully
4. Delete the CloudFormation stack: `aws cloudformation delete-stack --stack-name <stack-name>`

The teardown script performs the following operations in order:
1. Deletes all collections associated with the endpoint
2. Removes all storage gateways (S3, POSIX, etc.)
3. Removes the endpoint registration from Globus
4. Stops Globus services on the instance

If the teardown script encounters errors, you may need to manually remove resources from the Globus web UI before stack deletion.

## Troubleshooting Deployment Issues

When troubleshooting CloudFormation deployment failures:

1. Check CloudFormation event logs for specific error messages
2. Ensure all referenced resource attributes exist (e.g., PublicDnsName vs. PublicIp)
3. Verify IAM permissions for all actions performed in UserData scripts
4. Ensure proper resource signaling with CreationPolicy and cfn-signal
5. Check for S3 bucket accessibility before attempting connector setup
6. Verify that the subscription ID is valid when deploying connectors
7. Review deployment logs on the instance:
   - Main deployment logs: `/var/log/user-data.log` and `/var/log/cloud-init-output.log`
   - Globus setup log (most detailed): `/var/log/globus-setup.log`
   - Deployment summary: `/home/ubuntu/deployment-summary.txt`
   - Version check debug info: Look for "Detected Globus Connect Server version" in logs
   - Auth configuration issues: Look for ClientId/ClientSecret issues in config files
   - Package installation issues: Check if Globus packages are correctly installed with `dpkg -l | grep globus`
   - Verify the Globus command path with `which globus-connect-server`
8. For version compatibility issues:
   - Check the raw version output: `globus-connect-server --version`
   - Verify script correctly extracts the package version number
   - For version "globus-connect-server, package 5.4.83, cli 1.0.58", ensure "5.4.83" is extracted
   - Compare with required minimum version 5.4.61
9. For ROLLBACK_COMPLETE status, focus on the resource that initiated the rollback
10. For parameter handling issues:
    - Multi-word values must be properly quoted in all commands
    - Parameter values like "Amazon Web Services" should be preserved with spaces intact
11. **Verify network connectivity:**
    - Ensure the instance has a public IP address assigned (check Public DNS or IP in the EC2 console)
    - Confirm security groups allow Globus ports (443, 2811, 7512, 50000-51000)
    - Test connectivity from the internet to the public endpoint
12. **Shell script syntax issues:**
    - Check for mismatched `if`/`fi` statements in bash scripts
    - Avoid using `EOF` as a heredoc delimiter within complex if/else blocks
    - Prefer multiple `echo` statements over heredocs for creating files in complex control structures
    - Validate shell scripts with `bash -n scriptname.sh` before deployment
    - For complex scripts, consider simplifying nested conditional blocks to avoid syntax errors

## Parameter Requirements

### Required Parameters

- **AWS Parameters**:
  - `KeyName`: Name of an existing AWS EC2 KeyPair (not a local SSH key)
  - `VpcId`: VPC to deploy Globus Connect Server into
  - `SubnetId`: Subnet within the selected VPC
  - `AvailabilityZone`: The Availability Zone to launch the instance in

- **Globus Parameters**:
  - `GlobusOwner`: Identity username of the endpoint owner (e.g., user@example.edu)
    - **CRITICAL**: This value must be a valid Globus identity username
    - Required by Globus for endpoint registration
    - No default value is provided - must be explicitly set
  - `GlobusContactEmail`: Email address for the support contact
    - Visible to users of the endpoint for support inquiries
    - Default is "admin@example.com" but should be customized with a valid contact email
  - For Globus Connect Server < 5.4.67:
    - `GlobusClientId`: Globus Auth client ID
    - `GlobusClientSecret`: Globus Auth client secret

All other parameters are optional with appropriate defaults.

### Parameter Flow

The template passes parameters to the setup script as environment variables:
1. CloudFormation template parameters (e.g., `GlobusOwner`) are passed to the EC2 instance as environment variables (`GLOBUS_OWNER`)
2. The main setup script uses these variables directly for configuration
3. For manual troubleshooting, the values are also stored in files like `/home/ubuntu/globus-owner.txt`
4. The helper script uses these variables with fallbacks to set proper command parameters

### Endpoint Owner Reset

The template includes functionality to reset the endpoint owner after setup:

- **ResetEndpointOwner**: Controls whether to automatically reset the endpoint owner (default: "true")
- **DefaultAdminIdentity**: The identity to use as the endpoint owner (should be set to a real user, not service identity)

The endpoint owner reset process:
1. Automatically runs at the end of the setup process after all gateways are created
2. First sets owner-string with `globus-connect-server endpoint set-owner-string`
3. Then sets owner with `globus-connect-server endpoint set-owner`
4. **CRITICAL**: This order is required to maintain permissions throughout the process

The primary owner is set to the value in DefaultAdminIdentity. If DefaultAdminIdentity is not provided, owner reset is skipped.
**IMPORTANT**: Owner reset requires DefaultAdminIdentity to be set - no fallbacks are used.

This improves endpoint visibility in the Globus web UI by setting a human-readable owner rather than a service identity.

## Code Style Guidelines

- **YAML**: Use 2-space indentation, explicit mapping of types
- **CloudFormation**: 
  - Follow AWS best practices for resource naming
  - Boolean parameters must use String type with "true"/"false" as AllowedValues
  - Use !Condition for referencing conditions in !And or !Or functions
  - Always include CreationPolicy with appropriate ResourceSignal timeout for EC2 instances
  - For EC2 instances, ensure UserData scripts always signal completion status to CloudFormation
  - Verify resource attributes exist before referencing them (e.g., use PublicDnsName instead of PublicIp)
  - **CRITICAL**: Ensure EC2 instances have public network access either through:
    - NetworkInterfaces with AssociatePublicIpAddress: true, or
    - Elastic IP with proper association to the instance
  - **Operating System**: Template is designed for Ubuntu 22.04 LTS
    - Use apt package manager commands (apt-get)
    - Use /home/ubuntu as the home directory path
    - Use Ubuntu deb repositories for software installation
- **Markdown**: Use ATX-style headers (# Header), proper heading hierarchy
- **Naming Conventions**: Use PascalCase for CloudFormation resources and outputs, camelCase for parameters
- **Error Handling**: 
  - Implement robust error handling in user-data scripts with error trapping
  - Use handle_error function to consistently report and exit on critical failures
  - Include validation for external resources before attempting to use them
  - Implement retry logic for operations that may fail intermittently
- **Documentation**: Maintain comprehensive documentation in the docs/ directory
- **Resource Tags**: Consistently tag all resources with "Name" at minimum
- **IAM Permissions**: Ensure EC2 instances have all necessary permissions for their operations (e.g., ec2:CreateTags)