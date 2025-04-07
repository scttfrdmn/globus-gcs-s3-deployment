# Using Globus CLI for S3 Bucket Transfers

Here's how to use the Globus command line interface (CLI) to transfer files to and from your S3 bucket connected through Globus Connect Server:

## 1. Install Globus CLI

First, install the Globus CLI on your local machine:

```bash
# Install using pip
pip install globus-cli

# Verify installation
globus --version
```

## 2. Authenticate with Globus

```bash
# Log in to Globus
globus login

# This will open a browser window to complete authentication
# Follow the prompts to authorize the CLI
```

## 3. Find Your Endpoint IDs

```bash
# Find your Globus Connect Server endpoint
globus endpoint search "MyGlobusEndpoint"

# Note the endpoint ID, which looks like: a1b2c3d4-5678-90ef-ghij-klmnopqrstuv

# For transfer destination, find another endpoint
# For example, search for Globus tutorial endpoint
globus endpoint search "Globus Tutorial Endpoint"
```

## 4. List Files in Your S3 Bucket

```bash
# Replace ENDPOINT_ID with your endpoint ID
ENDPOINT_ID="your-endpoint-id"

# List the contents of your endpoint (showing available connectors)
globus ls "${ENDPOINT_ID}:/"

# List files in your S3 bucket through the connector
# Note: The path typically includes the connector name, e.g., "/s3_storage/"
globus ls "${ENDPOINT_ID}:/s3_storage/"
```

## 5. Transfer Files

### Option 1: One-time Transfer

```bash
# Set source and destination endpoints
SOURCE_ENDPOINT="your-endpoint-id"
DEST_ENDPOINT="destination-endpoint-id"

# Start transfer from S3 bucket to destination
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/path/to/file.txt" "${DEST_ENDPOINT}:/path/to/destination/" --label "S3 file transfer"

# Transfer multiple files
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/path/to/folder/" "${DEST_ENDPOINT}:/path/to/destination/" --recursive --label "S3 folder transfer"
```

### Option 2: Using Batch Transfer File

```bash
# Create a batch file with transfer instructions
cat > transfer.txt << EOF
/s3_storage/file1.txt /destination/file1.txt
/s3_storage/file2.txt /destination/file2.txt
/s3_storage/folder/ /destination/folder/ -r
EOF

# Execute batch transfer
globus transfer "${SOURCE_ENDPOINT}" "${DEST_ENDPOINT}" --batch transfer.txt --label "Batch S3 transfer"
```

## 6. Monitor Transfer

```bash
# List recent transfers
globus task list

# Get details of a specific transfer
globus task show TASK_ID

# Wait for transfer to complete
globus task wait TASK_ID
```

## 7. Additional Useful Commands

### Check Endpoint Details

```bash
# View detailed endpoint information
globus endpoint show ENDPOINT_ID

# Check connector details 
globus ls -l "${ENDPOINT_ID}:/" --features
```

### Verify Server-Side Configuration

```bash
# SSH into your Globus server
ssh -i your-key.pem ec2-user@<instance-public-dns>

# Check connector status
globus-connect-server storage-gateway list

# Check specific connector details
globus-connect-server storage-gateway show --connector-id s3_storage
```

### Synchronize Directories

```bash
# Sync from S3 to destination (similar to rsync)
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/folder/" "${DEST_ENDPOINT}:/destination/" --sync-level=checksum --recursive --label "S3 sync"
```

## 8. Automation Example

Here's a simple script to automate a regular S3 backup to another endpoint:

```bash
#!/bin/bash
# s3_backup.sh - Scheduled S3 bucket backup via Globus

SOURCE_ENDPOINT="your-endpoint-id"
DEST_ENDPOINT="destination-endpoint-id"
LABEL="Scheduled S3 Backup $(date +%Y-%m-%d)"

# Start the transfer
TASK_ID=$(globus transfer "${SOURCE_ENDPOINT}:/s3_storage/" "${DEST_ENDPOINT}:/backups/$(date +%Y-%m-%d)/" --recursive --label "${LABEL}" --jmespath 'task_id' -F json)

echo "Transfer initiated with task ID: ${TASK_ID}"

# Optional: wait for completion
globus task wait "${TASK_ID}"
echo "Transfer complete!"
```