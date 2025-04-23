# Parameter and Command Reference

This reference documents all CloudFormation parameters and CLI commands for managing Globus Connect Server with S3 integration.

## CloudFormation Parameters

### Required AWS Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|:--------:|--------|
| KeyName | EC2 key pair name for SSH access | ✓ | - |
| VpcId | VPC to deploy into | ✓ | - |
| SubnetId | Subnet within the VPC | ✓ | - |
| AvailabilityZone | AWS Availability Zone | ✓ | - |

### Required Globus Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|:--------:|--------|
| GlobusDisplayName | Display name for the endpoint | ✓ | - |
| GlobusOrganization | Organization name | ✓ | - |
| GlobusOwner | Identity username (e.g., user@example.edu) | ✓ | - |
| GlobusContactEmail | Support contact email | ✓ | admin@example.com |
| GlobusClientId | Client UUID from service account | ✓ | - |
| GlobusClientSecret | Client secret from service account | ✓ | - |
| GlobusProjectId | Globus Auth project ID | ✓ | - |

### Required S3 Connector Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|:--------:|--------|
| GlobusSubscriptionId | Subscription ID | ✓ | - |
| GlobusS3Domain | Allowed domain for S3 paths (e.g., "s3://*") | ✓ | - |
| S3BucketName | Name of S3 bucket to connect | ✓ | - |

### Optional Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|:--------:|--------|
| EnableS3Connector | Whether to enable S3 connector | ✗ | true |
| DeploymentType | "Integration" or "Production" | ✗ | Integration |
| InstanceType | EC2 instance type | ✗ | m6i.xlarge |
| ForceElasticIP | Force allocation of Elastic IP | ✗ | false |
| ResetEndpointOwner | Reset endpoint owner after setup | ✗ | true |
| EndpointResetOwnerTarget | Which identity to set as owner | ✗ | GlobusOwner |
| GlobusProjectName | Project name if creating new project | ✗ | - |
| GlobusProjectAdmin | Project admin if different from owner | ✗ | - |
| DefaultAdminIdentity | Identity to grant admin access | ✗ | - |

## Globus CLI Commands

### Endpoint Management

| Command | Description | Example |
|---------|-------------|----------|
| globus endpoint search | Find endpoints by name | `globus endpoint search "My Endpoint"` |
| globus endpoint show | View endpoint details | `globus endpoint show ENDPOINT_ID` |

### File Operations

| Command | Description | Example |
|---------|-------------|----------|
| globus ls | List files on endpoint | `globus ls "ENDPOINT_ID:/path/"` |
| globus transfer | Transfer files between endpoints | `globus transfer "SOURCE:/file.txt" "DEST:/file.txt"` |
| globus task list | List recent transfer tasks | `globus task list` |
| globus task show | View transfer task details | `globus task show TASK_ID` |
| globus task wait | Wait for task completion | `globus task wait TASK_ID` |

### Group Management

| Command | Description | Example |
|---------|-------------|----------|
| globus group create | Create a new group | `globus group create "Group Name"` |
| globus group list | List your groups | `globus group list` |
| globus group show | Show group details | `globus group show GROUP_ID` |
| globus group member add | Add member to group | `globus group member add GROUP_ID user@example.org` |
| globus group member list | List group members | `globus group member list GROUP_ID` |
| globus group member remove | Remove member from group | `globus group member remove GROUP_ID user@example.org` |

## Globus Connect Server Commands

### Endpoint Management

| Command | Description | Example |
|---------|-------------|----------|
| globus-connect-server endpoint setup | Create endpoint | `globus-connect-server endpoint setup --organization "Org" --owner "user@example.org" "Display Name"` |
| globus-connect-server endpoint show | View endpoint details | `globus-connect-server endpoint show` |
| globus-connect-server endpoint remove | Remove endpoint | `globus-connect-server endpoint remove` |

### Storage Gateway Management

| Command | Description | Example |
|---------|-------------|----------|
| globus-connect-server storage-gateway create s3 | Create S3 gateway | `globus-connect-server storage-gateway create s3 --domain "s3://*"` |
| globus-connect-server storage-gateway list | List gateways | `globus-connect-server storage-gateway list` |
| globus-connect-server storage-gateway show | Show gateway details | `globus-connect-server storage-gateway show GATEWAY_ID` |
| globus-connect-server storage-gateway delete | Delete gateway | `globus-connect-server storage-gateway delete GATEWAY_ID` |

### Collection Management

| Command | Description | Example |
|---------|-------------|----------|
| globus-connect-server collection list | List collections | `globus-connect-server collection list` |
| globus-connect-server collection create | Create collection | `globus-connect-server collection create GATEWAY_ID PATH "Display Name"` |
| globus-connect-server collection delete | Delete collection | `globus-connect-server collection delete COLLECTION_ID` |

### Permission Management

| Command | Description | Example |
|---------|-------------|----------|
| globus-connect-server endpoint permission create | Create permission | `globus-connect-server endpoint permission create --identity user@example.org --permissions rw --collection COLLECTION_ID` |
| globus-connect-server acl create | Create access control | `globus-connect-server acl create --permissions read,write --principal "user@example.org" --path "/path/"` |

## Version Compatibility

| Globus Version | Compatibility | Notes |
|----------------|---------------|-------|
| 5.4.61+ | Fully Compatible | All features supported |
| 5.4.67+ | Updated Auth | No client credentials needed |
| < 5.4.61 | Not Compatible | Deployment will fail with version check |

## Environment Variables

### Configuration Variables

| Variable | Purpose | Default |
|----------|---------|--------|
| GCS_CLI_CLIENT_ID | Service credential client ID | - |
| GCS_CLI_CLIENT_SECRET | Service credential client secret | - |

### Debugging Variables

| Variable | Purpose | Default |
|----------|---------|--------|
| DEBUG_SKIP_VERSION_CHECK | Bypass version compatibility check | false |
| DEBUG_SKIP_DUPLICATE_CHECK | Skip duplicate endpoint checking | false |
| SHOULD_FAIL | Controls stack failure behavior | no |

## Related Topics

- [Installation Guide](./installation.md) - Prerequisites and deployment instructions
- [Operations Guide](./operations.md) - Working with collections and transfers
- [Troubleshooting Guide](./troubleshooting.md) - Common issues and solutions
