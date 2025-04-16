#!/bin/bash
# Teardown script for Globus Connect Server before CloudFormation deletion
# This script helps clean up Globus Connect Server resources before deleting the CloudFormation stack

# First run the setup script to create the exports file
if [ -f /home/ubuntu/setup-env.sh ]; then
  bash /home/ubuntu/setup-env.sh
  
  # Now source the generated exports file to set variables in the current shell
  if [ -f /home/ubuntu/globus-env-exports.sh ]; then
    echo "Sourcing exported environment variables..."
    source /home/ubuntu/globus-env-exports.sh
  else
    echo "Error: exports file not created by setup-env.sh"
    exit 1
  fi
else
  echo "Error: environment setup script not found. Please run this from an instance with a deployed Globus Connect Server."
  exit 1
fi

# Verify that critical variables were set
if [ -z "$GCS_CLI_CLIENT_ID" ] || [ -z "$GCS_CLI_CLIENT_SECRET" ] || [ -z "$GCS_CLI_ENDPOINT_ID" ]; then
  echo "Error: Critical environment variables are not set correctly"
  echo "Please manually run: source /home/ubuntu/globus-env-exports.sh"
  exit 1
fi

echo "Environment variables successfully loaded."

echo "=== Starting Globus Connect Server teardown ==="
echo "This script will remove all Globus Connect Server resources from this endpoint."
echo "It should be run BEFORE attempting to delete the CloudFormation stack."
echo

# Check if we have required environment variables
if [ -z "$GCS_CLI_ENDPOINT_ID" ]; then
  echo "Error: No endpoint ID found in environment variables."
  # Try to get it from the file
  if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
    export GCS_CLI_ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt)
    echo "Found endpoint ID in file: $GCS_CLI_ENDPOINT_ID"
  else
    echo "Error: Could not determine endpoint ID. Endpoint may not exist or not be properly configured."
    exit 1
  fi
fi

# Function to check if a command succeeded
check_success() {
  if [ $? -eq 0 ]; then
    echo "✓ Success: $1"
  else
    echo "✗ Failed: $1"
    echo "  You may need to perform this step manually or investigate further."
  fi
}

# Get collection IDs properly by focusing on the actual UUIDs
get_collection_ids() {
  local output=$(globus-connect-server collection list 2>/dev/null)
  echo "$output" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" || true
}

# Get storage gateway IDs properly by focusing on the actual UUIDs
get_gateway_ids() {
  local output=$(globus-connect-server storage-gateway list 2>/dev/null)
  echo "$output" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" || true
}

# Step 1: Delete collections first
echo "Step 1: Deleting collections..."
# Get all collection IDs
COLLECTIONS=$(get_collection_ids)

if [ -z "$COLLECTIONS" ]; then
  echo "No collections found to delete."
else
  for collection in $COLLECTIONS; do
    echo "Deleting collection: $collection"
    globus-connect-server collection delete "$collection"
    check_success "Delete collection $collection"
  done
fi

# Step 2: Delete storage gateways
echo
echo "Step 2: Deleting storage gateways..."
GATEWAYS=$(get_gateway_ids)

if [ -z "$GATEWAYS" ]; then
  echo "No storage gateways found to delete."
else
  for gateway in $GATEWAYS; do
    echo "Deleting gateway: $gateway"
    globus-connect-server storage-gateway delete "$gateway"
    check_success "Delete gateway $gateway"
  done
fi

# Step 3: Delete the endpoint (uses "remove" not "delete")
echo
echo "Step 3: Deleting endpoint..."
echo "Endpoint ID: $GCS_CLI_ENDPOINT_ID"
globus-connect-server endpoint remove
check_success "Delete endpoint $GCS_CLI_ENDPOINT_ID"

# Step 4: Clean up Globus services
echo
echo "Step 4: Cleaning up Globus services..."
# First try without sudo, and if that fails, try with sudo
if systemctl stop globus-gridftp-server 2>/dev/null; then
  check_success "Stop GridFTP service"
else
  echo "Regular stop failed, trying with sudo..."
  sudo systemctl stop globus-gridftp-server 2>/dev/null
  check_success "Stop GridFTP service with sudo"
fi

if systemctl stop apache2 2>/dev/null; then
  check_success "Stop Apache service"
else
  echo "Regular stop failed, trying with sudo..."
  sudo systemctl stop apache2 2>/dev/null
  check_success "Stop Apache service with sudo"
fi

# Create a marker file to indicate successful cleanup
echo
echo "Creating marker file for successful teardown..."
echo "Globus Connect Server teardown completed at $(date)" > /home/ubuntu/TEARDOWN_COMPLETED.txt
echo "You can now safely delete the CloudFormation stack." >> /home/ubuntu/TEARDOWN_COMPLETED.txt

echo
echo "=== Globus Connect Server teardown completed ==="
echo "You can now safely delete the CloudFormation stack."
echo "You may want to verify that the endpoint is no longer visible in the Globus web UI."
echo "To check, visit: https://app.globus.org/endpoints"
echo
echo "NOTE: If you need to run any other Globus commands manually, remember to source"
echo "the environment variables in your current shell first with:"
echo "  source /home/ubuntu/globus-env-exports.sh"