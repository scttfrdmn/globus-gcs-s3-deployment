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

## Parameter Requirements

### Required Parameters

- **AWS Parameters**:
  - `KeyName`: Name of an existing AWS EC2 KeyPair (not a local SSH key)
  - `VpcId`: VPC to deploy Globus Connect Server into
  - `SubnetId`: Subnet within the selected VPC
  - `AvailabilityZone`: The Availability Zone to launch the instance in

- **Globus Parameters**:
  - `GlobusOwner`: Identity username of the endpoint owner
  - `GlobusContactEmail`: Email address for the support contact
  - For Globus Connect Server < 5.4.67:
    - `GlobusClientId`: Globus Auth client ID
    - `GlobusClientSecret`: Globus Auth client secret

All other parameters are optional with appropriate defaults.

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