#!/bin/bash
# Script to reestablish Globus environment variables for manual debugging

# Set constants
GLOBUS_DIR="/home/ubuntu"
LOG_FILE="/var/log/globus-setup.log"

# Logging function
log() {
  echo "$(date) - $*" | tee -a "$LOG_FILE"
}

echo "Setting up Globus environment variables for debugging..."

# Load client credentials 
if [ -f "${GLOBUS_DIR}/globus-client-id.txt" ] && [ -f "${GLOBUS_DIR}/globus-client-secret.txt" ]; then
  export GCS_CLI_CLIENT_ID="$(cat "${GLOBUS_DIR}/globus-client-id.txt")"
  export GCS_CLI_CLIENT_SECRET="$(cat "${GLOBUS_DIR}/globus-client-secret.txt")"
  echo "✓ Set GCS_CLI_CLIENT_ID and GCS_CLI_CLIENT_SECRET from credentials files"
else
  echo "⚠️  Warning: Client credentials files not found"
fi

# Load endpoint ID if available
if [ -f "${GLOBUS_DIR}/endpoint-uuid.txt" ]; then
  export GCS_CLI_ENDPOINT_ID="$(cat "${GLOBUS_DIR}/endpoint-uuid.txt")"
  echo "✓ Set GCS_CLI_ENDPOINT_ID to $(cat "${GLOBUS_DIR}/endpoint-uuid.txt")"
else
  echo "⚠️  Warning: Endpoint UUID file not found"
fi

# Set node ID if available
if [ -f "${GLOBUS_DIR}/node-id.txt" ]; then
  export GLOBUS_NODE_ID="$(cat "${GLOBUS_DIR}/node-id.txt")"
  echo "✓ Set GLOBUS_NODE_ID to $(cat "${GLOBUS_DIR}/node-id.txt")"
else
  echo "Node ID file not found (node may not be set up yet)"
fi

# Load other variables from files if they exist
echo "Loading additional variables from files..."

# Set up basic variables
for var_file in globus-display-name.txt globus-organization.txt globus-owner.txt globus-contact-email.txt globus-project-id.txt; do
  if [ -f "${GLOBUS_DIR}/${var_file}" ]; then
    var_name="GLOBUS_$(echo ${var_file%%.txt} | tr 'a-z-' 'A-Z_')"
    # Use read to preserve spaces in the variable value
    value=$(cat "${GLOBUS_DIR}/${var_file}")
    export ${var_name}="${value}"
    echo "✓ Set ${var_name}"
  fi
done

# Load S3 bucket name if available
if [ -f "${GLOBUS_DIR}/s3-bucket-name.txt" ]; then
  export S3_BUCKET_NAME="$(cat "${GLOBUS_DIR}/s3-bucket-name.txt")"
  echo "✓ Set S3_BUCKET_NAME to $S3_BUCKET_NAME"
fi

# Load subscription ID if available
if [ -f "${GLOBUS_DIR}/subscription-id.txt" ]; then
  export GLOBUS_SUBSCRIPTION_ID="$(cat "${GLOBUS_DIR}/subscription-id.txt")"
  echo "✓ Set GLOBUS_SUBSCRIPTION_ID to $GLOBUS_SUBSCRIPTION_ID"
fi

# Generate a file that can be sourced to set variables in the current shell
cat > /home/ubuntu/globus-env-exports.sh << EOF
# Generated environment variables for Globus
export GCS_CLI_CLIENT_ID="$GCS_CLI_CLIENT_ID"
export GCS_CLI_CLIENT_SECRET="$GCS_CLI_CLIENT_SECRET"
export GCS_CLI_ENDPOINT_ID="$GCS_CLI_ENDPOINT_ID"
export GLOBUS_NODE_ID="$GLOBUS_NODE_ID"
EOF

# Add the other GLOBUS_ variables
for var_name in $(compgen -v | grep "^GLOBUS_"); do
  if [ "$var_name" != "GLOBUS_DIR" ] && [ "$var_name" != "GLOBUS_NODE_ID" ]; then
    echo "export $var_name=\"${!var_name}\"" >> /home/ubuntu/globus-env-exports.sh
  fi
done

# Add S3 bucket name if set
if [ -n "$S3_BUCKET_NAME" ]; then
  echo "export S3_BUCKET_NAME=\"$S3_BUCKET_NAME\"" >> /home/ubuntu/globus-env-exports.sh
fi

# Make sure the file is executable
chmod +x /home/ubuntu/globus-env-exports.sh

# Show all environment variables that have been set
echo ""
echo "Globus environment variables are now set:"
echo "---------------------------------------------"
env | grep -E "GCS_CLI_|GLOBUS_|S3_BUCKET_NAME" | sort

echo ""
echo "To persist these variables in your current shell, run:"
echo "source /home/ubuntu/globus-env-exports.sh"
echo ""
echo "You can now run Globus commands using these credentials."
echo "Examples:"
echo "  globus-connect-server endpoint show"
echo "  globus-connect-server node list"

# Example commands for debugging
echo ""
echo "Debugging commands:"
echo "---------------------------------------------"
echo "Check endpoint status: globus-connect-server endpoint show"
echo "List nodes: globus-connect-server node list"
echo "Get subscription status: globus-connect-server endpoint show | grep subscription"
echo "Test S3 connector: globus-connect-server storage-gateway create s3 \"$S3_BUCKET_NAME\""
echo "View CloudFormation logs: tail -n 100 /var/log/cloud-init-output.log"
echo "View Globus setup logs: tail -n 100 /var/log/globus-setup.log"
echo "View detailed debug logs: tail -n 100 ${GLOBUS_DIR}/debug.log"
