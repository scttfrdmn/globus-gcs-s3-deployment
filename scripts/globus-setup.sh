#!/bin/bash
# Simplified Globus Connect Server installation script
# Only performs basic installation and endpoint setup
# REQUIRES: Globus Connect Server 5.4.61 or higher

# Enable error handling
set -e
set -o pipefail

# Create log file
LOG_FILE="/var/log/globus-setup.log"
touch "$LOG_FILE" 2>/dev/null || {
  LOG_FILE="/tmp/globus-setup.log"
  touch "$LOG_FILE"
}

# Logging function
log() {
  echo "$(date) - $*" | tee -a "$LOG_FILE"
}

log "=== Starting Simplified Globus Connect Server setup: $(date) ==="

# Install Globus Connect Server
log "Installing dependencies..."
apt-get update
apt-get install -y curl wget apt-transport-https ca-certificates

# Add Globus repository
log "Adding Globus repository..."
cd /tmp
curl -LOs https://downloads.globus.org/globus-connect-server/stable/installers/repo/deb/globus-repo_latest_all.deb
if [ ! -f /tmp/globus-repo_latest_all.deb ]; then
  log "Failed to download Globus repository package."
  exit 1
fi

dpkg -i /tmp/globus-repo_latest_all.deb
apt-get update

# Install Globus Connect Server package
log "Installing Globus Connect Server package..."
apt-get install -y globus-connect-server54

# Verify installation
log "Verifying installation..."
which globus-connect-server > /home/ubuntu/globus-command-path.txt 2>&1 || 
  echo "Command not found" > /home/ubuntu/globus-command-path.txt

if ! command -v globus-connect-server &> /dev/null; then
  log "Globus Connect Server installation failed."
  exit 1
fi

# Get GCS version
GCS_VERSION_RAW=$(globus-connect-server --version 2>&1)
log "Raw version output: $GCS_VERSION_RAW"

# Extract package version (format: "package X.Y.Z")
GCS_VERSION_PACKAGE=$(echo "$GCS_VERSION_RAW" | grep -o "package [0-9]\+\.[0-9]\+\.[0-9]\+" | awk '{print $2}' || echo "")

if [ -n "$GCS_VERSION_PACKAGE" ]; then
  GCS_VERSION="$GCS_VERSION_PACKAGE"
  log "Using package version: $GCS_VERSION"
else
  # Fallback to any version number pattern
  GCS_VERSION=$(echo "$GCS_VERSION_RAW" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "5.4.61")
  log "Using fallback version: $GCS_VERSION"
fi

# Save environment variables to files in Ubuntu home
mkdir -p /home/ubuntu
echo "$GLOBUS_CLIENT_ID" > /home/ubuntu/globus-client-id.txt
echo "$GLOBUS_CLIENT_SECRET" > /home/ubuntu/globus-client-secret.txt
echo "$GLOBUS_DISPLAY_NAME" > /home/ubuntu/globus-display-name.txt
echo "$GLOBUS_ORGANIZATION" > /home/ubuntu/globus-organization.txt
echo "$GLOBUS_OWNER" > /home/ubuntu/globus-owner.txt
echo "$GLOBUS_CONTACT_EMAIL" > /home/ubuntu/globus-contact-email.txt
echo "$GLOBUS_PROJECT_ID" > /home/ubuntu/globus-project-id.txt
chmod 600 /home/ubuntu/globus-client-*.txt

# Set environment variables for Globus CLI authentication
export GCS_CLI_CLIENT_ID="$GLOBUS_CLIENT_ID"
export GCS_CLI_CLIENT_SECRET="$GLOBUS_CLIENT_SECRET"

# Prepare endpoint setup command
log "Setting up endpoint with display name: $GLOBUS_DISPLAY_NAME"
SETUP_CMD="globus-connect-server endpoint setup"
SETUP_CMD+=" --organization \"$GLOBUS_ORGANIZATION\""
SETUP_CMD+=" --contact-email \"$GLOBUS_CONTACT_EMAIL\""
SETUP_CMD+=" --owner \"$GLOBUS_OWNER\""
SETUP_CMD+=" --dont-set-advertised-owner"  # For automation reliability
SETUP_CMD+=" --agree-to-letsencrypt-tos"

# Add project ID if specified
if [ -n "$GLOBUS_PROJECT_ID" ]; then
  SETUP_CMD+=" --project-id \"$GLOBUS_PROJECT_ID\""
fi

# Execute the setup command and capture output
log "Running endpoint setup command..."
SETUP_OUTPUT=$(eval $SETUP_CMD "\"$GLOBUS_DISPLAY_NAME\"" 2>&1)
SETUP_EXIT_CODE=$?

# Save output to file
echo "$SETUP_OUTPUT" > /home/ubuntu/endpoint-setup-output.txt

# Check setup result
if [ $SETUP_EXIT_CODE -ne 0 ]; then
  log "Endpoint setup failed with exit code $SETUP_EXIT_CODE"
  log "Setup Output: $SETUP_OUTPUT"
  exit 1
fi

# Extract endpoint UUID from output
log "Extracting endpoint UUID from command output..."
ENDPOINT_UUID=$(echo "$SETUP_OUTPUT" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)

if [ -n "$ENDPOINT_UUID" ]; then
  log "Successfully extracted endpoint UUID: $ENDPOINT_UUID"
  # Save UUID to file
  echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
  export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
  
  # Create endpoint URL file
  echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" > /home/ubuntu/endpoint-url.txt
else
  log "Could not extract endpoint UUID from output"
  # Try to get endpoint details
  ENDPOINT_SHOW=$(globus-connect-server endpoint show 2>&1)
  echo "$ENDPOINT_SHOW" > /home/ubuntu/endpoint-details.txt
  
  # Try to extract UUID from endpoint show output
  ENDPOINT_UUID=$(echo "$ENDPOINT_SHOW" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
  
  if [ -n "$ENDPOINT_UUID" ]; then
    log "Found endpoint UUID from show command: $ENDPOINT_UUID"
    echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
    export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
    echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" > /home/ubuntu/endpoint-url.txt
  fi
fi

# Create a simple helper script to show endpoint details
cat > /home/ubuntu/show-endpoint.sh << 'EOF'
#!/bin/bash
# Helper script to show Globus endpoint details

# Set credentials
if [ -f /home/ubuntu/globus-client-id.txt ] && [ -f /home/ubuntu/globus-client-secret.txt ]; then
  export GCS_CLI_CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
  export GCS_CLI_CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
fi

# Check if we have UUID
if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
  export GCS_CLI_ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt)
  echo "Endpoint UUID: $GCS_CLI_ENDPOINT_ID"
  globus-connect-server endpoint show
  echo ""
  echo "Access the endpoint at: https://app.globus.org/file-manager?origin_id=$GCS_CLI_ENDPOINT_ID"
else
  echo "No endpoint UUID found. Trying endpoint show command..."
  globus-connect-server endpoint show
fi
EOF

chmod +x /home/ubuntu/show-endpoint.sh
chown ubuntu:ubuntu /home/ubuntu/show-endpoint.sh

# Create deployment summary
cat > /home/ubuntu/deployment-summary.txt << EOF
=== Globus Connect Server Deployment Summary ===
Deployment completed: $(date)

Endpoint Details:
- Display Name: $GLOBUS_DISPLAY_NAME
- Owner: $GLOBUS_OWNER
- Organization: $GLOBUS_ORGANIZATION
- Contact Email: $GLOBUS_CONTACT_EMAIL
- UUID: ${ENDPOINT_UUID:-Not available}

Access Information:
- Web URL: https://app.globus.org/file-manager?origin_id=${ENDPOINT_UUID:-MISSING_UUID}

Helper Scripts:
- /home/ubuntu/show-endpoint.sh: Show endpoint details
EOF

# Set permissions
chown -R ubuntu:ubuntu /home/ubuntu/

log "=== Globus Connect Server setup completed: $(date) ==="
exit 0