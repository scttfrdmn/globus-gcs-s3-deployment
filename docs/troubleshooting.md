# Troubleshooting Guide

This guide helps diagnose and resolve common issues with the Globus Connect Server S3 deployment.

## Deployment Issues

### CloudFormation Failures

| Error | Cause | Solution |
|-------|-------|----------|
| CREATE_FAILED for EC2 instance | UserData script failure | Check logs at `/var/log/cloud-init-output.log` and `/var/log/user-data.log` |
| Stack deletion fails | Globus resources not removed | SSH to instance and run `/home/ubuntu/teardown-globus.sh` first |
| Parameter validation failed | Missing required parameter | Check parameters, especially Globus credentials |

To view stack failure events:

```bash
# Show failed resources in table format
aws cloudformation describe-stack-events --stack-name globus-gcs \
  --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].{Resource:LogicalResourceId,Type:ResourceType,Reason:ResourceStatusReason}" \
  --output table
```

### Authentication Problems

| Error | Cause | Solution |
|-------|-------|----------|
| "Can not set the advertised owner when using client credentials" | Service identity configuration | Use `--dont-set-advertised-owner` flag (managed by template) |
| "Failed to perform any Auth flows" | Missing Project ID or credentials | Verify `GlobusProjectId`, Client ID and Secret |
| "You have multiple existing projects" | Missing Project ID | Set correct `GlobusProjectId` parameter |
| "Authentication/Authorization failed" | Service account not an admin | Add service account as admin to your project |
| "Credentials environment variables set: 0" | Environment variables not set | Verify the script sets `GCS_CLI_CLIENT_ID` and `GCS_CLI_CLIENT_SECRET` |

### Version Compatibility Issues

| Issue | Cause | Solution |
|-------|------|----------|
| "Version X.Y.Z is not supported" | Incompatible Globus version | Ensure server has Globus Connect Server 5.4.61+ |
| "Failed to parse version" | Version output format issue | Set `DEBUG_SKIP_VERSION_CHECK="true"` |

### S3 Connector Issues

| Error | Cause | Solution |
|-------|-------|----------|
| "Failed to set subscription ID" | Missing subscription permissions | Add service account to subscription group as admin |
| S3 connector features don't work | Subscription issue | Have a subscription manager run: `globus-connect-server endpoint set-subscription-id DEFAULT` |
| Domain restrictions error | Incorrect domain format | Ensure `GlobusS3Domain` is properly set (e.g., "s3://*") |

## Runtime Issues

### Collection Access Problems

| Issue | Cause | Solution |
|-------|------|----------|
| Can't find endpoint | Visibility/ownership issue | Check `/home/ubuntu/endpoint-uuid.txt` for UUID and search directly |
| Can't see your endpoint | Owner visibility problem | Run `globus-connect-server endpoint set-owner-string "your-email@example.com"` |
| Can't access collections | Permission issue | Verify permissions with `globus-connect-server acl list` |

### Transfer Failures

| Issue | Cause | Solution |
|-------|------|----------|
| S3 access denied | IAM permissions | Check instance role permissions for S3 access |
| Transfer stuck pending | Network connectivity | Verify security groups allow proper Globus ports |
| File not found | Path issues | Verify paths with `globus ls` command |

## Diagnostic Resources

### Log Files

| File | Purpose | Important Content |
|------|---------|-------------------|
| `/var/log/user-data.log` | Deployment script execution | Overall deployment process |
| `/var/log/cloud-init-output.log` | Cloud-init output | Early initialization issues |
| `/var/log/globus-setup.log` | Globus-specific setup | Detailed Globus configuration |
| `/home/ubuntu/deployment-summary.txt` | Deployment overview | Configuration summary |
| `/home/ubuntu/globus-setup-failed.txt` | Failure information | Created when setup fails |
| `/home/ubuntu/cloud-init-debug.log` | Detailed progress | Step-by-step installation |
| `/home/ubuntu/cloud-init-modules.log` | Module issues | Script module errors |
| `/home/ubuntu/globus-setup-complete.log` | Full setup log | Complete setup output |
| `/home/ubuntu/endpoint-reset-owner.txt` | Owner reset results | Shows owner configuration |

### Helper Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `/home/ubuntu/setup-env.sh` | Set up environment variables | `source /home/ubuntu/setup-env.sh` |
| `/home/ubuntu/run-globus-setup.sh` | Manually run Globus setup | `bash /home/ubuntu/run-globus-setup.sh` |
| `/home/ubuntu/teardown-globus.sh` | Remove Globus resources | `bash /home/ubuntu/teardown-globus.sh` |
| `/home/ubuntu/collect-diagnostics.sh` | Gather diagnostic info | `bash /home/ubuntu/collect-diagnostics.sh` |

## Manual Troubleshooting

### SSH to the instance

```bash
# Get the public address
PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)

# Connect via SSH
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS
```

### Check authentication variables

```bash
# Check environment variables
env | grep GCS_CLI

# Source environment variables
source /home/ubuntu/globus-env-exports.sh
```

### Manual setup with explicit credentials

```bash
# Get parameters from files
CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
DISPLAY_NAME=$(cat /home/ubuntu/globus-display-name.txt)
OWNER=$(cat /home/ubuntu/globus-owner.txt)
EMAIL=$(cat /home/ubuntu/globus-contact-email.txt)

# Set environment variables
export GCS_CLI_CLIENT_ID="$CLIENT_ID"
export GCS_CLI_CLIENT_SECRET="$CLIENT_SECRET"

# Run setup script with debug output
bash -x /home/ubuntu/run-globus-setup.sh \
  "$CLIENT_ID" "$CLIENT_SECRET" "$DISPLAY_NAME" "Organization Name" "$OWNER" "$EMAIL"
```

### Verify Globus resources

```bash
# Check Globus server status
systemctl status globus-gridftp-server

# Check endpoint details
globus-connect-server endpoint show

# List storage gateways
globus-connect-server storage-gateway list

# List collections
globus-connect-server collection list
```

## Teardown Process

### Using the Teardown Script

```bash
# SSH to the instance
ssh -i your-key-pair.pem ubuntu@$PUBLIC_DNS

# Run the teardown script
bash /home/ubuntu/teardown-globus.sh

# After successful teardown, delete the stack
aws cloudformation delete-stack --stack-name globus-gcs
```

### Manual Teardown Steps

```bash
# Source environment variables
source /home/ubuntu/setup-env.sh

# Delete all collections
COLLECTIONS=$(globus-connect-server collection list 2>/dev/null | grep -v "^ID" | awk '{print $1}')
for collection in $COLLECTIONS; do
  echo "Deleting collection: $collection"
  globus-connect-server collection delete "$collection"
done

# Delete all storage gateways
GATEWAYS=$(globus-connect-server storage-gateway list 2>/dev/null | grep -v "^ID" | awk '{print $1}')
for gateway in $GATEWAYS; do
  echo "Deleting gateway: $gateway"
  globus-connect-server storage-gateway delete "$gateway"
done

# Delete the endpoint
globus-connect-server endpoint delete
```

## Related Topics

- [Installation Guide](./installation.md) - Prerequisites and deployment instructions
- [Operations Guide](./operations.md) - Working with collections and transfers
- [Parameter Reference](./reference.md) - Complete parameter documentation
