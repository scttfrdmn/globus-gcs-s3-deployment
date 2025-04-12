# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- CloudFormation validation: `aws cloudformation validate-template --template-body file://globus-gcs-s3-template.yaml`
- CloudFormation linting: `cfn-lint globus-gcs-s3-template.yaml`
- YAML linting: `yamllint globus-gcs-s3-template.yaml`
- Markdown linting: `markdownlint README.md docs/*.md`
- CloudFormation deployment check: `aws cloudformation describe-stack-events --stack-name globus-gcs | grep -A 2 "FAILED"`

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
   - Deployment summary: `/home/ec2-user/deployment-summary.txt`
   - Auth configuration issues: Look for ClientId/ClientSecret issues in config files
8. For ROLLBACK_COMPLETE status, focus on the resource that initiated the rollback
9. **Verify network connectivity:**
   - Ensure the instance has a public IP address assigned (check Public DNS or IP in the EC2 console)
   - Confirm security groups allow Globus ports (443, 2811, 7512, 50000-51000)
   - Test connectivity from the internet to the public endpoint

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