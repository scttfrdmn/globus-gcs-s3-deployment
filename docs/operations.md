# Globus Operations Guide

This guide covers working with Globus collections, file transfers, and access management for your deployed S3 endpoint.

## Collection Types Overview

| Collection Type | Description | S3 Compatible |
|-----------------|-------------|:-------------:|
| Server Collections | Created via Globus Connect Server deployment | ✓ |
| Personal Collections | Created via Globus Connect Personal (laptops, desktops) | ✗ |
| Guest Collections | Virtual entry points hosted on Server Collections | ✓ |
| Mapped Collections | Logical organization of directories | ✓ |

### S3 Integration Architecture

```
AWS Account
   └── S3 Bucket
       └── Connected via S3 Storage Connector (with domain restrictions)
           └── Exposed through Globus Server Collection
               └── Accessible via Globus Transfer Service
```

### Key Integration Points

1. **Authentication Layers**:
   - AWS credentials (IAM role) authenticate to S3
   - Globus credentials authenticate users to the collection

2. **Domain Restrictions**:
   - S3 paths are restricted based on `GlobusS3Domain` parameter (e.g., "s3://*")
   - Provides additional security and access control

## File Transfer Operations

### Installing the Globus CLI

```bash
# Install with pip
pip install globus-cli

# Verify installation
globus --version

# Authenticate
globus login
```

### Basic File Transfers

```bash
# Find your endpoint IDs
globus endpoint search "MyGlobusEndpoint"

# List files in your S3 bucket
globus ls "ENDPOINT_ID:/s3_storage/"

# Transfer a file
globus transfer "SOURCE_ENDPOINT:/s3_storage/file.txt" "DEST_ENDPOINT:/destination/" --label "S3 file transfer"

# Transfer a directory recursively
globus transfer "SOURCE_ENDPOINT:/s3_storage/folder/" "DEST_ENDPOINT:/destination/" --recursive --label "Folder transfer"
```

### Advanced Transfer Options

```bash
# Batch transfer with file
cat > transfer.txt << EOF
/s3_storage/file1.txt /destination/file1.txt
/s3_storage/file2.txt /destination/file2.txt
/s3_storage/folder/ /destination/folder/ -r
EOF

globus transfer "SOURCE_ENDPOINT" "DEST_ENDPOINT" --batch transfer.txt --label "Batch transfer"

# Synchronize directories (similar to rsync)
globus transfer "SOURCE_ENDPOINT:/s3_storage/folder/" "DEST_ENDPOINT:/destination/" --sync-level=checksum --recursive --label "S3 sync"
```

### Monitoring Transfers

```bash
# List recent transfers
globus task list

# Get details about a transfer
globus task show TASK_ID

# Wait for transfer to complete
globus task wait TASK_ID
```

## Collection Management

### Server Collection Access

```bash
# View endpoint details
globus endpoint show ENDPOINT_ID

# SSH to your Globus server
ssh -i your-key.pem ubuntu@<instance-ip>

# List storage gateways
globus-connect-server storage-gateway list

# List collections
globus-connect-server collection list
```

### Setting Access Permissions

```bash
# Grant access to a user
globus-connect-server endpoint permission create --identity user@example.org --permissions rw --collection COLLECTION_ID

# Grant user access to specific path
globus-connect-server acl create \
  --permissions read,write \
  --principal "user@example.org" \
  --path "/s3_storage/project/"
```

## Groups Management

### Creating and Managing Groups

```bash
# Create a group
GROUP_ID=$(globus group create "Research Team" \
  --description "Research team access for our project" \
  --format JSON | jq -r '.id')

# Add members with different roles
globus group member add $GROUP_ID "admin@example.org" --role admin
globus group member add $GROUP_ID "manager@example.org" --role manager
globus group member add $GROUP_ID "user@example.org" --role member

# List group members
globus group member list $GROUP_ID
```

### Using Groups with Collections

```bash
# Grant access to a group
globus-connect-server acl create \
  --permissions read,write \
  --principal "urn:globus:groups:id:${GROUP_ID}" \
  --path "/s3_storage/shared-data/"
```

## Script Example: Automated S3 Backup

```bash
#!/bin/bash
# s3_backup.sh - Scheduled S3 bucket backup via Globus

SOURCE_ENDPOINT="your-endpoint-id"
DEST_ENDPOINT="destination-endpoint-id"
LABEL="Scheduled S3 Backup $(date +%Y-%m-%d)"

# Start the transfer
TASK_ID=$(globus transfer "${SOURCE_ENDPOINT}:/s3_storage/" "${DEST_ENDPOINT}:/backups/$(date +%Y-%m-%d)/" \
  --recursive --label "${LABEL}" --jmespath 'task_id' -F json)

echo "Transfer initiated with task ID: ${TASK_ID}"

# Optional: wait for completion
globus task wait "${TASK_ID}"
echo "Transfer complete!"
```

## Related Topics

- [Installation Guide](./installation.md) - Prerequisites and deployment instructions
- [Parameter Reference](./reference.md) - Complete parameter documentation
- [Troubleshooting Guide](./troubleshooting.md) - Common issues and solutions
