#!/bin/bash
# Simplified Globus Connect Server installation script
# Only performs basic installation and endpoint setup
# REQUIRES: Globus Connect Server 5.4.61 or higher

# NOT using set -e to ensure we continue collecting diagnostics even after errors
# Instead we'll check error codes at key points and create detailed logs
# set -e
# set -o pipefail

# Create a trap to capture and log information on any error
trap 'echo "ERROR: Command failed at line $LINENO with exit code $?. Command: $BASH_COMMAND" | tee -a /home/ubuntu/setup-error.log' ERR

# Create log file with multiple fallbacks
LOG_FILE="/var/log/globus-setup.log"
touch "$LOG_FILE" 2>/dev/null || {
  LOG_FILE="/home/ubuntu/globus-setup.log"
  touch "$LOG_FILE" 2>/dev/null || {
    LOG_FILE="/tmp/globus-setup.log"
    touch "$LOG_FILE" 2>/dev/null || {
      LOG_FILE=""
      echo "WARNING: Unable to create any log file, proceeding without logging to file"
    }
  }
}

# Logging function
log() {
  local timestamp=$(date)
echo "$timestamp - $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "$timestamp - $*"
}

# Enhanced debug logging
debug_log() {
  echo "=== DEBUG: $(date) - $* ===" | tee -a "$LOG_FILE" 
  
  # Make sure debug.log exists and is writable
  if [ ! -f "/home/ubuntu/debug.log" ]; then
    touch "/home/ubuntu/debug.log" 2>/dev/null || true
    chmod 644 "/home/ubuntu/debug.log" 2>/dev/null || true
  fi
  
  # Append to debug log
  echo "=== DEBUG: $(date) - $* ===" >> "/home/ubuntu/debug.log" 2>/dev/null || true
}

# Function to set permissions on a collection
set_collection_permissions() {
  local collection_id=$1
  local admin_identity=$2
  local collection_name=$3
  
  if [ -z "$admin_identity" ]; then
    log "No admin identity provided for collection $collection_name ($collection_id). Skipping permission setup."
    return 0
  fi

  log "Setting permissions for collection $collection_name ($collection_id)..."
  log "Granting read/write access to $admin_identity"
  
  PERM_CMD="globus-connect-server endpoint permission create --identity \"$admin_identity\" --permissions rw --collection $collection_id"
  log "Running command: $PERM_CMD"
  
  PERM_OUTPUT=$(eval $PERM_CMD 2>&1)
  PERM_EXIT_CODE=$?
  
  if [ $PERM_EXIT_CODE -eq 0 ]; then
    log "Successfully granted permissions to $admin_identity for collection $collection_id"
    echo "$PERM_OUTPUT" > "/home/ubuntu/$collection_id-permissions.txt"
    return 0
  else
    log "Failed to set permissions for collection $collection_id with exit code $PERM_EXIT_CODE"
    echo "Failed to set permissions for collection $collection_name ($collection_id)" > "/home/ubuntu/${collection_name}_PERMISSION_FAILED.txt"
    echo "Command: $PERM_CMD" >> "/home/ubuntu/${collection_name}_PERMISSION_FAILED.txt"
    echo "Exit code: $PERM_EXIT_CODE" >> "/home/ubuntu/${collection_name}_PERMISSION_FAILED.txt"
    echo "Output: $PERM_OUTPUT" >> "/home/ubuntu/${collection_name}_PERMISSION_FAILED.txt"
    return 1
  fi
}

# Make sure /home/ubuntu exists and is writable
mkdir -p /home/ubuntu 2>/dev/null || true
chmod 755 /home/ubuntu 2>/dev/null || true

log "=== Starting Simplified Globus Connect Server setup: $(date) ==="
debug_log "Starting setup with UID=$(id -u), EUID=$(id -eu), USER=$USER"

# Log debug information about environment variables
debug_log "Starting with environment variables:"
debug_log "GLOBUS_DISPLAY_NAME=$GLOBUS_DISPLAY_NAME"
debug_log "GLOBUS_ORGANIZATION=$GLOBUS_ORGANIZATION"
debug_log "GLOBUS_OWNER=$GLOBUS_OWNER"
debug_log "GLOBUS_CONTACT_EMAIL=$GLOBUS_CONTACT_EMAIL"
debug_log "GLOBUS_PROJECT_ID=${GLOBUS_PROJECT_ID:0:5}..." # Truncating for security
debug_log "ENABLE_S3_CONNECTOR=$ENABLE_S3_CONNECTOR"
debug_log "S3_BUCKET_NAME=$S3_BUCKET_NAME"
debug_log "GLOBUS_SUBSCRIPTION_ID=$GLOBUS_SUBSCRIPTION_ID"
debug_log "PRESERVE_INSTANCE=$PRESERVE_INSTANCE"

# Verify critical S3 parameters if S3 connector is enabled
if [ "$ENABLE_S3_CONNECTOR" = "true" ]; then
  debug_log "S3 connector is enabled, verifying required parameters"
  
  if [ -z "$S3_BUCKET_NAME" ]; then
    debug_log "ERROR: S3_BUCKET_NAME is empty but S3 connector is enabled"
    echo "ERROR: S3_BUCKET_NAME parameter is required when S3 connector is enabled" > /home/ubuntu/S3_PARAMETER_ERROR.txt
  else
    debug_log "S3_BUCKET_NAME is set to: $S3_BUCKET_NAME"
  fi
  
  if [ -z "$GLOBUS_SUBSCRIPTION_ID" ]; then
    debug_log "ERROR: GLOBUS_SUBSCRIPTION_ID is empty but S3 connector is enabled"
    echo "ERROR: GLOBUS_SUBSCRIPTION_ID parameter is required when S3 connector is enabled" > /home/ubuntu/S3_PARAMETER_ERROR.txt
  else
    debug_log "GLOBUS_SUBSCRIPTION_ID is set to: $GLOBUS_SUBSCRIPTION_ID"
  fi
fi

# Install Globus Connect Server
log "Installing dependencies..."
apt-get update
apt-get install -y curl wget apt-transport-https ca-certificates python3-pip

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

# Install Globus CLI for easier management
log "Installing Globus CLI..."
pip3 install -q globus-cli

# Configure Globus CLI with credentials for easier command-line usage
log "Configuring Globus CLI..."
mkdir -p ~/.globus
cat > ~/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF

# Also configure for ubuntu user
mkdir -p /home/ubuntu/.globus
cat > /home/ubuntu/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF
chown -R ubuntu:ubuntu /home/ubuntu/.globus

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
chmod 755 /home/ubuntu

# Save environment variables ensuring we don't create empty files
[ -n "$GLOBUS_CLIENT_ID" ] && echo "$GLOBUS_CLIENT_ID" > /home/ubuntu/globus-client-id.txt || echo "MISSING" > /home/ubuntu/globus-client-id.txt
[ -n "$GLOBUS_CLIENT_SECRET" ] && echo "$GLOBUS_CLIENT_SECRET" > /home/ubuntu/globus-client-secret.txt || echo "MISSING" > /home/ubuntu/globus-client-secret.txt
[ -n "$GLOBUS_DISPLAY_NAME" ] && echo "$GLOBUS_DISPLAY_NAME" > /home/ubuntu/globus-display-name.txt || echo "MISSING" > /home/ubuntu/globus-display-name.txt
[ -n "$GLOBUS_ORGANIZATION" ] && echo "$GLOBUS_ORGANIZATION" > /home/ubuntu/globus-organization.txt || echo "MISSING" > /home/ubuntu/globus-organization.txt
[ -n "$GLOBUS_OWNER" ] && echo "$GLOBUS_OWNER" > /home/ubuntu/globus-owner.txt || echo "MISSING" > /home/ubuntu/globus-owner.txt
[ -n "$GLOBUS_CONTACT_EMAIL" ] && echo "$GLOBUS_CONTACT_EMAIL" > /home/ubuntu/globus-contact-email.txt || echo "MISSING" > /home/ubuntu/globus-contact-email.txt
[ -n "$GLOBUS_PROJECT_ID" ] && echo "$GLOBUS_PROJECT_ID" > /home/ubuntu/globus-project-id.txt || echo "MISSING" > /home/ubuntu/globus-project-id.txt

# Save subscription and S3 information
[ -n "$GLOBUS_SUBSCRIPTION_ID" ] && echo "$GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/subscription-id.txt || echo "NONE" > /home/ubuntu/subscription-id.txt
[ -n "$S3_BUCKET_NAME" ] && echo "$S3_BUCKET_NAME" > /home/ubuntu/s3-bucket-name.txt || echo "NONE" > /home/ubuntu/s3-bucket-name.txt
[ -n "$S3_GATEWAY_DISPLAY_NAME" ] && echo "$S3_GATEWAY_DISPLAY_NAME" > /home/ubuntu/s3-gateway-display-name.txt || echo "S3 Bucket Gateway" > /home/ubuntu/s3-gateway-display-name.txt
[ -n "$S3_GATEWAY_DOMAIN" ] && echo "$S3_GATEWAY_DOMAIN" > /home/ubuntu/s3-gateway-domain.txt || echo "amazon.com" > /home/ubuntu/s3-gateway-domain.txt

# Save admin identities
[ -n "$COLLECTION_ADMIN_IDENTITY" ] && echo "$COLLECTION_ADMIN_IDENTITY" > /home/ubuntu/collection-admin-identity.txt || echo "NONE" > /home/ubuntu/collection-admin-identity.txt
[ -n "$DEFAULT_ADMIN_IDENTITY" ] && echo "$DEFAULT_ADMIN_IDENTITY" > /home/ubuntu/default-admin-identity.txt || echo "NONE" > /home/ubuntu/default-admin-identity.txt

# Determine which admin identity to use for collections
# First try collection-specific admin, then default admin
if [ -n "$COLLECTION_ADMIN_IDENTITY" ]; then
  COLLECTION_ADMIN="$COLLECTION_ADMIN_IDENTITY"
  log "Using specified CollectionAdminIdentity: $COLLECTION_ADMIN"
elif [ -n "$DEFAULT_ADMIN_IDENTITY" ]; then
  COLLECTION_ADMIN="$DEFAULT_ADMIN_IDENTITY"
  log "Using DefaultAdminIdentity for collections: $COLLECTION_ADMIN"
else
  COLLECTION_ADMIN=""
  log "WARNING: No admin identity specified for collections. Only the service account ($GLOBUS_OWNER) will have access."
fi

echo "$COLLECTION_ADMIN" > /home/ubuntu/effective-collection-admin.txt

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
log "Command: $SETUP_CMD \"$GLOBUS_DISPLAY_NAME\""

# Create the endpoint-setup-output.txt file to ensure it exists
touch /home/ubuntu/endpoint-setup-output.txt 2>/dev/null
chmod 644 /home/ubuntu/endpoint-setup-output.txt 2>/dev/null

# Run the command and save output to a file we know exists
eval $SETUP_CMD "\"$GLOBUS_DISPLAY_NAME\"" > /home/ubuntu/endpoint-setup-output.txt 2>&1
SETUP_EXIT_CODE=$?

# Get the output from the file
SETUP_OUTPUT=$(cat /home/ubuntu/endpoint-setup-output.txt)

# Check setup result
if [ $SETUP_EXIT_CODE -ne 0 ]; then
  log "Endpoint setup failed with exit code $SETUP_EXIT_CODE"
  log "Setup Output (first 200 chars): ${SETUP_OUTPUT:0:200}..."
  
  # Save detailed error information
  echo "Endpoint setup command: $SETUP_CMD \"$GLOBUS_DISPLAY_NAME\"" > /home/ubuntu/ENDPOINT_SETUP_FAILED.txt
  echo "Exit code: $SETUP_EXIT_CODE" >> /home/ubuntu/ENDPOINT_SETUP_FAILED.txt
  echo "Full output:" >> /home/ubuntu/ENDPOINT_SETUP_FAILED.txt
  echo "$SETUP_OUTPUT" >> /home/ubuntu/ENDPOINT_SETUP_FAILED.txt
  
  # Continue execution to collect more diagnostic information instead of exiting
  debug_log "Continuing despite endpoint setup failure to collect diagnostics"
else
  log "Endpoint setup completed successfully"
  debug_log "Endpoint setup output (first 200 chars): ${SETUP_OUTPUT:0:200}..."
fi

# Extract endpoint UUID from output, looking specifically for the "Created endpoint UUID" pattern
log "Extracting endpoint UUID from command output..."
# First try to find the line with "Created endpoint" which contains the UUID
CREATED_LINE=$(echo "$SETUP_OUTPUT" | grep "Created endpoint")
if [ -n "$CREATED_LINE" ]; then
  # Extract UUID from the Created endpoint line
  ENDPOINT_UUID=$(echo "$CREATED_LINE" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
  log "Found UUID in 'Created endpoint' line: $ENDPOINT_UUID"
else
  # Fallback to scanning entire output for UUID pattern
  ENDPOINT_UUID=$(echo "$SETUP_OUTPUT" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
  log "Extracted UUID using pattern matching: $ENDPOINT_UUID"
fi

# Save domain name if present
DOMAIN_NAME=$(echo "$SETUP_OUTPUT" | grep "domain_name" | awk '{print $2}')
if [ -n "$DOMAIN_NAME" ]; then
  log "Found domain name: $DOMAIN_NAME"
  echo "$DOMAIN_NAME" > /home/ubuntu/endpoint-domain.txt
fi

if [ -n "$ENDPOINT_UUID" ]; then
  log "Successfully extracted endpoint UUID: $ENDPOINT_UUID"
  # Save UUID to various locations for reliability
  echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
  echo "ENDPOINT_UUID=$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid-export.sh
  chmod +x /home/ubuntu/endpoint-uuid-export.sh
  
  # Set environment variable for current session
  export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
  
  # Create endpoint URL file
  echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" > /home/ubuntu/endpoint-url.txt
  
  # Check if a subscription ID was provided to make the endpoint managed
  if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
    log "Associating endpoint with subscription ID: $GLOBUS_SUBSCRIPTION_ID"
    debug_log "Setting up subscription with ID: $GLOBUS_SUBSCRIPTION_ID"
    
    # Save subscription ID to file for reference
    echo "$GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/subscription-id.txt
    
    # Run the command to set the subscription ID
    log "Running: globus-connect-server endpoint update --subscription-id $GLOBUS_SUBSCRIPTION_ID"
    debug_log "Environment for subscription update: GCS_CLI_CLIENT_ID=${GCS_CLI_CLIENT_ID:0:5}..., GCS_CLI_CLIENT_SECRET=${GCS_CLI_CLIENT_SECRET:0:3}..., GCS_CLI_ENDPOINT_ID=$GCS_CLI_ENDPOINT_ID"
    
    debug_log "Executing subscription update command..."
    SUBSCRIPTION_OUTPUT=$(globus-connect-server endpoint update --subscription-id "$GLOBUS_SUBSCRIPTION_ID" 2>&1)
    SUBSCRIPTION_EXIT_CODE=$?
    debug_log "Subscription update completed with exit code: $SUBSCRIPTION_EXIT_CODE"
    
    # Save output to file
    echo "$SUBSCRIPTION_OUTPUT" > /home/ubuntu/subscription-update-output.txt
    debug_log "Subscription update output (truncated): ${SUBSCRIPTION_OUTPUT:0:200}..."
    
    if [ $SUBSCRIPTION_EXIT_CODE -eq 0 ]; then
      log "Successfully associated endpoint with subscription"
      echo "Endpoint is now managed under subscription ID: $GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/SUBSCRIPTION_SUCCESS.txt
      echo "$SUBSCRIPTION_OUTPUT" >> /home/ubuntu/SUBSCRIPTION_SUCCESS.txt
    else
      log "Failed to associate endpoint with subscription"
      echo "ERROR: Failed to associate endpoint with subscription ID: $GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "Command: globus-connect-server endpoint update --subscription-id $GLOBUS_SUBSCRIPTION_ID" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "Exit code: $SUBSCRIPTION_EXIT_CODE" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "Output: $SUBSCRIPTION_OUTPUT" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "IMPORTANT: Setting a subscription requires proper permissions:" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "1. The service account used (${GLOBUS_OWNER}) must be configured as an administrator" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "   in the subscription membership group." >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "2. This configuration requires an existing membership group administrator to set." >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "To manually set the subscription later, run:" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
      echo "globus-connect-server endpoint update --subscription-id $GLOBUS_SUBSCRIPTION_ID" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
    fi
  else
    log "No subscription ID provided, endpoint will have basic features only"
  fi
  
  # Now run the node setup command with the public IP
  log "Now setting up the Globus Connect Server node..."
  
  # Get the instance's public IP address - try multiple methods
  debug_log "Attempting to determine public IP address using multiple methods"
  
  # First try the EC2 metadata service
  PUBLIC_IP=$(curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/public-ipv4 || echo "")
  debug_log "EC2 metadata service IP result: ${PUBLIC_IP:-none}"
  
  if [ -z "$PUBLIC_IP" ]; then
    # Fallback method - try to get it from public interface
    PUBLIC_IP=$(curl -s --connect-timeout 3 https://checkip.amazonaws.com || 
                curl -s --connect-timeout 3 https://api.ipify.org || 
                curl -s --connect-timeout 3 https://ipv4.icanhazip.com || echo "")
    debug_log "Public IP service result: ${PUBLIC_IP:-none}"
  fi
  
  if [ -z "$PUBLIC_IP" ]; then
    # Final fallback - try to determine from network interfaces
    PUBLIC_IP=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^10\." | grep -v "^172\." | grep -v "^192\.168" | head -1 || echo "")
    debug_log "Network interface IP result: ${PUBLIC_IP:-none}"
  fi
  
  # If all methods fail, try one last desperate attempt with ifconfig
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 || echo "")
    debug_log "ifconfig IP result: ${PUBLIC_IP:-none}"
  fi
  
  if [ -z "$PUBLIC_IP" ]; then
    log "WARNING: Could not determine public IP address"
    echo "WARNING: Could not determine public IP address" > /home/ubuntu/MISSING_IP.txt
    echo "Please run the node setup command manually with your public IP:" >> /home/ubuntu/MISSING_IP.txt
    echo "sudo globus-connect-server node setup --ip-address YOUR_PUBLIC_IP" >> /home/ubuntu/MISSING_IP.txt
  else
    log "Using public IP address: $PUBLIC_IP"
    echo "$PUBLIC_IP" > /home/ubuntu/public-ip.txt
    
    # Run node setup with the detected IP
    log "Running: sudo globus-connect-server node setup --ip-address $PUBLIC_IP"
    NODE_SETUP_OUTPUT=$(sudo globus-connect-server node setup --ip-address "$PUBLIC_IP" 2>&1)
    NODE_SETUP_EXIT_CODE=$?
    
    # Save output to file
    echo "$NODE_SETUP_OUTPUT" > /home/ubuntu/node-setup-output.txt
    
    if [ $NODE_SETUP_EXIT_CODE -eq 0 ]; then
      log "Node setup completed successfully"
      
      # Reload Apache as suggested by the output
      log "Reloading Apache service..."
      sudo systemctl reload apache2
      
      # Also restart for good measure
      log "Restarting Apache service..."
      sudo systemctl restart apache2
      
      # Get the node ID using node list command
      log "Getting node ID using node list command..."
      debug_log "Attempting to get node ID from node list command"
      NODE_LIST_OUTPUT=$(globus-connect-server node list 2>&1 || echo "Command failed")
      echo "$NODE_LIST_OUTPUT" > /home/ubuntu/node-list-output.txt
      debug_log "Node list output (truncated): ${NODE_LIST_OUTPUT:0:200}..."
      
      # Extract the node ID from the node list output by matching with our public IP
      # The output format is: ID | IP Addresses | Status
      # First try to find a line containing our public IP
      NODE_ID=$(echo "$NODE_LIST_OUTPUT" | grep -v "^ID" | grep "$PUBLIC_IP" | awk '{print $1}')
      
      if [ -n "$NODE_ID" ]; then
        log "Found node ID for IP $PUBLIC_IP: $NODE_ID"
        echo "$NODE_ID" > /home/ubuntu/node-id.txt
        
        # Get more details about the node
        log "Getting node details..."
        NODE_SHOW_OUTPUT=$(globus-connect-server node show "$NODE_ID" 2>&1)
        echo "$NODE_SHOW_OUTPUT" > /home/ubuntu/node-details.txt
      else
        # If IP not found in output, try just getting the first node as fallback
        NODE_ID=$(echo "$NODE_LIST_OUTPUT" | grep -v "^ID" | head -1 | awk '{print $1}')
        
        if [ -n "$NODE_ID" ]; then
          log "No node found with IP $PUBLIC_IP, using first available node: $NODE_ID"
          echo "$NODE_ID" > /home/ubuntu/node-id.txt
          
          # Get more details about the node
          log "Getting node details..."
          NODE_SHOW_OUTPUT=$(globus-connect-server node show "$NODE_ID" 2>&1)
          echo "$NODE_SHOW_OUTPUT" > /home/ubuntu/node-details.txt
        else
          log "Could not find any node ID - will try the node list command again with environment variables"
          
          # Try another approach with environment variables explicitly set
          if [ -n "$GCS_CLI_CLIENT_ID" ] && [ -n "$GCS_CLI_CLIENT_SECRET" ] && [ -n "$GCS_CLI_ENDPOINT_ID" ]; then
            NODE_LIST_OUTPUT=$(GCS_CLI_CLIENT_ID="$GCS_CLI_CLIENT_ID" GCS_CLI_CLIENT_SECRET="$GCS_CLI_CLIENT_SECRET" GCS_CLI_ENDPOINT_ID="$GCS_CLI_ENDPOINT_ID" globus-connect-server node list 2>&1)
            
            # Try to find by IP again
            NODE_ID=$(echo "$NODE_LIST_OUTPUT" | grep -v "^ID" | grep "$PUBLIC_IP" | awk '{print $1}')
            
            if [ -z "$NODE_ID" ]; then
              # If that fails, just get the first node
              NODE_ID=$(echo "$NODE_LIST_OUTPUT" | grep -v "^ID" | head -1 | awk '{print $1}')
            fi
            
            if [ -n "$NODE_ID" ]; then
              log "Found node ID on second attempt: $NODE_ID"
              echo "$NODE_ID" > /home/ubuntu/node-id.txt
              
              # Get more details about the node
              NODE_SHOW_OUTPUT=$(globus-connect-server node show "$NODE_ID" 2>&1)
              echo "$NODE_SHOW_OUTPUT" > /home/ubuntu/node-details.txt
            else
              log "Could not find node ID after multiple attempts"
            fi
          else
            log "Missing environment variables needed to retry node list command"
          fi
        fi
      fi
      
      # Check status of key services
      log "Checking status of Globus services..."
      systemctl status globus-gridftp-server --no-pager | grep -E "Active:|Main PID:" > /home/ubuntu/gridftp-status.txt
      systemctl status apache2 --no-pager | grep -E "Active:|Main PID:" > /home/ubuntu/apache-status.txt
      
      # Setup is successful

      # Check if S3 gateway is requested and if subscription is set 
      if [ -n "$ENABLE_S3_CONNECTOR" ] && [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ -n "$S3_BUCKET_NAME" ] && [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
        log "Creating S3 storage gateway for bucket: $S3_BUCKET_NAME"
        debug_log "S3 Connector Variables: ENABLE_S3_CONNECTOR=$ENABLE_S3_CONNECTOR, S3_BUCKET_NAME=$S3_BUCKET_NAME, GLOBUS_SUBSCRIPTION_ID=$GLOBUS_SUBSCRIPTION_ID"
        
        # Save S3 bucket name to file for reference
        echo "$S3_BUCKET_NAME" > /home/ubuntu/s3-bucket-name.txt
        
        # Get S3 gateway display name
        S3_GATEWAY_DISPLAY_NAME_VALUE=$(cat /home/ubuntu/s3-gateway-display-name.txt)
        S3_GATEWAY_DOMAIN_VALUE=$(cat /home/ubuntu/s3-gateway-domain.txt)
        
        # Set appropriate S3 command parameters
        S3_CMD="globus-connect-server storage-gateway create s3 --s3-endpoint https://s3.amazonaws.com --s3-user-credential"
        
        # Add domain parameter if defined and not empty (and not the default "NONE" value)
        if [ -n "$S3_GATEWAY_DOMAIN_VALUE" ] && [ "$S3_GATEWAY_DOMAIN_VALUE" != "NONE" ] && [ "$S3_GATEWAY_DOMAIN_VALUE" != "MISSING" ]; then
            debug_log "Adding domain parameter: $S3_GATEWAY_DOMAIN_VALUE"
            S3_CMD="$S3_CMD --domain \"$S3_GATEWAY_DOMAIN_VALUE\""
        else
            debug_log "No domain specified, omitting domain parameter"
        fi
        
        # Add display name as the positional argument at the end
        S3_CMD="$S3_CMD \"$S3_GATEWAY_DISPLAY_NAME_VALUE\""
        
        log "Running command: $S3_CMD"
        debug_log "Environment for S3 gateway creation: GCS_CLI_CLIENT_ID=${GCS_CLI_CLIENT_ID:0:5}..., GCS_CLI_CLIENT_SECRET=${GCS_CLI_CLIENT_SECRET:0:3}..., GCS_CLI_ENDPOINT_ID=$GCS_CLI_ENDPOINT_ID"
        
        # Execute the command
        debug_log "Executing S3 gateway command now..."
        S3_OUTPUT=$(eval $S3_CMD 2>&1)
        S3_EXIT_CODE=$?
        debug_log "S3 gateway command completed with exit code: $S3_EXIT_CODE, bucket: $S3_BUCKET_NAME"
        
        # Save output for reference
        echo "$S3_OUTPUT" > /home/ubuntu/s3-gateway-output.txt
        debug_log "S3 gateway output (truncated): ${S3_OUTPUT:0:200}..."
        
        if [ $S3_EXIT_CODE -eq 0 ]; then
          log "S3 gateway created successfully"
          
          # Extract the gateway ID from the output
          S3_GATEWAY_ID=$(echo "$S3_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
          if [ -n "$S3_GATEWAY_ID" ]; then
            log "Extracted S3 gateway ID: $S3_GATEWAY_ID"
            echo "$S3_GATEWAY_ID" > /home/ubuntu/s3-gateway-id.txt
            
            # Automatically create a default collection for the S3 gateway
            log "Creating default S3 collection..."
            DEFAULT_S3_COLLECTION_NAME="${S3_BUCKET_NAME}-collection"
            S3_COLLECTION_CMD="globus-connect-server collection create --storage-gateway \"$S3_GATEWAY_ID\" --display-name \"$DEFAULT_S3_COLLECTION_NAME\""
            log "Running command: $S3_COLLECTION_CMD"
            S3_COLLECTION_OUTPUT=$(eval $S3_COLLECTION_CMD 2>&1)
            S3_COLLECTION_EXIT_CODE=$?
            
            # Save output for reference
            echo "$S3_COLLECTION_OUTPUT" > /home/ubuntu/s3-collection-output.txt
            
            if [ $S3_COLLECTION_EXIT_CODE -eq 0 ]; then
              log "Default S3 collection created successfully"
              
              # Extract the collection ID from the output
              S3_COLLECTION_ID=$(echo "$S3_COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
              if [ -n "$S3_COLLECTION_ID" ]; then
                log "Extracted S3 collection ID: $S3_COLLECTION_ID"
                echo "$S3_COLLECTION_ID" > /home/ubuntu/s3-collection-id.txt
                echo "$DEFAULT_S3_COLLECTION_NAME" > /home/ubuntu/s3-collection-name.txt
                
                # Set permissions for the admin identity (if provided)
                if [ -n "$COLLECTION_ADMIN" ]; then
                  set_collection_permissions "$S3_COLLECTION_ID" "$COLLECTION_ADMIN" "$DEFAULT_S3_COLLECTION_NAME"
                  S3_PERM_STATUS=$?
                  if [ $S3_PERM_STATUS -eq 0 ]; then
                    echo "true" > /home/ubuntu/s3-collection-permissions-set.txt
                    log "Successfully set permissions for S3 collection"
                  else
                    echo "false" > /home/ubuntu/s3-collection-permissions-set.txt
                    log "Failed to set permissions for S3 collection"
                  fi
                else
                  log "No collection admin specified. S3 collection will only be accessible to the service account."
                  echo "false" > /home/ubuntu/s3-collection-permissions-set.txt
                fi
              else
                log "Could not extract S3 collection ID from output"
              fi
            else
              log "Failed to create default S3 collection with exit code $S3_COLLECTION_EXIT_CODE"
              echo "$S3_COLLECTION_OUTPUT" > /home/ubuntu/S3_COLLECTION_FAILED.txt
            fi
            
            # Create a helper script to create S3 collections
            cat > /home/ubuntu/create-s3-collection.sh << EOF
#!/bin/bash
# Helper script to create a collection for the S3 gateway

# Setup environment variables for Globus commands
source /home/ubuntu/globus-env.sh

# Check if we have the gateway ID
S3_GATEWAY_ID=\$(cat /home/ubuntu/s3-gateway-id.txt 2>/dev/null)
if [ -z "\$S3_GATEWAY_ID" ]; then
  echo "ERROR: S3 Gateway ID not found. Please make sure the S3 gateway was created."
  exit 1
fi

# Get collection name from argument or prompt
COLLECTION_NAME="\$1"
if [ -z "\$COLLECTION_NAME" ]; then
  echo -n "Enter collection name: "
  read COLLECTION_NAME
  if [ -z "\$COLLECTION_NAME" ]; then
    echo "ERROR: Collection name is required."
    exit 1
  fi
fi

# Create the collection
echo "Creating collection \"\$COLLECTION_NAME\" for S3 gateway with ID \$S3_GATEWAY_ID..."
globus-connect-server collection create --storage-gateway "\$S3_GATEWAY_ID" --display-name "\$COLLECTION_NAME"

# Check the result
if [ \$? -eq 0 ]; then
  echo "Collection created successfully!"
else
  echo "Failed to create collection."
  exit 1
fi
EOF
            chmod +x /home/ubuntu/create-s3-collection.sh
            chown ubuntu:ubuntu /home/ubuntu/create-s3-collection.sh
            log "Created helper script for manually creating S3 collections: /home/ubuntu/create-s3-collection.sh"
          else
            log "Could not extract S3 gateway ID from output"
          fi
        else
          log "Failed to create S3 gateway with exit code $S3_EXIT_CODE"
          debug_log "S3 gateway creation FAILED. Full output: $S3_OUTPUT"
          
          # Create detailed error file
          echo "Failed to create S3 gateway with exit code $S3_EXIT_CODE" > /home/ubuntu/S3_GATEWAY_FAILED.txt
          echo "Please check the output in s3-gateway-output.txt" >> /home/ubuntu/S3_GATEWAY_FAILED.txt
          echo "Command attempted: $S3_CMD" >> /home/ubuntu/S3_GATEWAY_FAILED.txt
          echo "" >> /home/ubuntu/S3_GATEWAY_FAILED.txt
          echo "Full command output:" >> /home/ubuntu/S3_GATEWAY_FAILED.txt
          echo "$S3_OUTPUT" >> /home/ubuntu/S3_GATEWAY_FAILED.txt
          
          # Create more detailed error file with troubleshooting info
          cat > /home/ubuntu/S3_CONNECTOR_TROUBLESHOOTING.txt << EOF
S3 Connector Setup Failed

Common issues:
1. Missing subscription ID or not an administrator - the account used for setup 
   must be a subscription administrator in the subscription membership group.
2. IAM permissions insufficient - the instance needs access to the S3 bucket
3. S3 bucket doesn't exist or is in a different region
4. S3 bucket format is incorrect

Command format: globus-connect-server storage-gateway create s3 [OPTIONS] DISPLAY_NAME

Command attempted: $S3_CMD
Exit code: $S3_EXIT_CODE
Output: 
$S3_OUTPUT

To set up manually after fixing the issue, run:
$S3_CMD

You can also get command help with:
globus-connect-server storage-gateway create s3 --help
EOF
        fi
      else
        if [ -n "$ENABLE_S3_CONNECTOR" ] && [ "$ENABLE_S3_CONNECTOR" = "true" ]; then
          if [ -z "$S3_BUCKET_NAME" ]; then
            log "S3 gateway creation requested but S3_BUCKET_NAME not provided"
            echo "ERROR: S3 gateway creation requested but S3_BUCKET_NAME not provided" > /home/ubuntu/S3_MISSING_BUCKET.txt
          fi
          
          if [ -z "$GLOBUS_SUBSCRIPTION_ID" ]; then
            log "S3 gateway creation requested but GLOBUS_SUBSCRIPTION_ID not provided (required for S3 connector)"
            echo "ERROR: S3 gateway creation requested but no subscription ID provided" > /home/ubuntu/S3_MISSING_SUBSCRIPTION.txt
            echo "The S3 connector requires a Globus subscription" >> /home/ubuntu/S3_MISSING_SUBSCRIPTION.txt
          fi
        else
          log "S3 gateway creation not requested (ENABLE_S3_CONNECTOR=$ENABLE_S3_CONNECTOR)"
        fi
      fi
      
      # Check if POSIX gateway is requested
      if [ -n "$ENABLE_POSIX_GATEWAY" ] && [ "$ENABLE_POSIX_GATEWAY" = "true" ] && [ -n "$POSIX_GATEWAY_NAME" ]; then
        log "Creating POSIX storage gateway: $POSIX_GATEWAY_NAME"
        
        # Optional domain parameter
        DOMAIN_PARAM=""
        if [ -n "$POSIX_GATEWAY_DOMAIN" ]; then
          DOMAIN_PARAM="--domain \"$POSIX_GATEWAY_DOMAIN\""
        fi
        
        # Create the POSIX gateway command
        GATEWAY_CMD="globus-connect-server storage-gateway create posix \"$POSIX_GATEWAY_NAME\" $DOMAIN_PARAM"
        log "Running command: $GATEWAY_CMD"
        
        # Execute the command
        GATEWAY_OUTPUT=$(eval $GATEWAY_CMD 2>&1)
        GATEWAY_EXIT_CODE=$?
        
        # Save output for reference
        echo "$GATEWAY_OUTPUT" > /home/ubuntu/posix-gateway-output.txt
        
        if [ $GATEWAY_EXIT_CODE -eq 0 ]; then
          log "POSIX gateway created successfully"
          
          # Extract the gateway ID from the output
          GATEWAY_ID=$(echo "$GATEWAY_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
          if [ -n "$GATEWAY_ID" ]; then
            log "Extracted POSIX gateway ID: $GATEWAY_ID"
            echo "$GATEWAY_ID" > /home/ubuntu/posix-gateway-id.txt
            
            # Automatically create a default collection for the POSIX gateway
            log "Creating default POSIX collection..."
            DEFAULT_POSIX_COLLECTION_NAME="${POSIX_GATEWAY_NAME}-collection"
            POSIX_COLLECTION_CMD="globus-connect-server collection create --storage-gateway \"$GATEWAY_ID\" --display-name \"$DEFAULT_POSIX_COLLECTION_NAME\""
            log "Running command: $POSIX_COLLECTION_CMD"
            POSIX_COLLECTION_OUTPUT=$(eval $POSIX_COLLECTION_CMD 2>&1)
            POSIX_COLLECTION_EXIT_CODE=$?
            
            # Save output for reference
            echo "$POSIX_COLLECTION_OUTPUT" > /home/ubuntu/posix-collection-output.txt
            
            if [ $POSIX_COLLECTION_EXIT_CODE -eq 0 ]; then
              log "Default POSIX collection created successfully"
              
              # Extract the collection ID from the output
              POSIX_COLLECTION_ID=$(echo "$POSIX_COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
              if [ -n "$POSIX_COLLECTION_ID" ]; then
                log "Extracted POSIX collection ID: $POSIX_COLLECTION_ID"
                echo "$POSIX_COLLECTION_ID" > /home/ubuntu/posix-collection-id.txt
                echo "$DEFAULT_POSIX_COLLECTION_NAME" > /home/ubuntu/posix-collection-name.txt
                
                # Set permissions for the admin identity (if provided)
                if [ -n "$COLLECTION_ADMIN" ]; then
                  set_collection_permissions "$POSIX_COLLECTION_ID" "$COLLECTION_ADMIN" "$DEFAULT_POSIX_COLLECTION_NAME"
                  POSIX_PERM_STATUS=$?
                  if [ $POSIX_PERM_STATUS -eq 0 ]; then
                    echo "true" > /home/ubuntu/posix-collection-permissions-set.txt
                    log "Successfully set permissions for POSIX collection"
                  else
                    echo "false" > /home/ubuntu/posix-collection-permissions-set.txt
                    log "Failed to set permissions for POSIX collection"
                  fi
                else
                  log "No collection admin specified. POSIX collection will only be accessible to the service account."
                  echo "false" > /home/ubuntu/posix-collection-permissions-set.txt
                fi
              else
                log "Could not extract POSIX collection ID from output"
              fi
            else
              log "Failed to create default POSIX collection with exit code $POSIX_COLLECTION_EXIT_CODE"
              echo "$POSIX_COLLECTION_OUTPUT" > /home/ubuntu/POSIX_COLLECTION_FAILED.txt
            fi
            
            # Create a helper script to create collections manually
            cat > /home/ubuntu/create-posix-collection.sh << EOF
#!/bin/bash
# Helper script to create a collection for the POSIX gateway

# Setup environment variables for Globus commands
source /home/ubuntu/globus-env.sh

# Check if we have the gateway ID
GATEWAY_ID=\$(cat /home/ubuntu/posix-gateway-id.txt 2>/dev/null)
if [ -z "\$GATEWAY_ID" ]; then
  echo "ERROR: Gateway ID not found. Please make sure the POSIX gateway was created."
  exit 1
fi

# Get collection name from argument or prompt
COLLECTION_NAME="\$1"
if [ -z "\$COLLECTION_NAME" ]; then
  echo -n "Enter collection name: "
  read COLLECTION_NAME
  if [ -z "\$COLLECTION_NAME" ]; then
    echo "ERROR: Collection name is required."
    exit 1
  fi
fi

# Create the collection
echo "Creating collection \"\$COLLECTION_NAME\" for POSIX gateway with ID \$GATEWAY_ID..."
globus-connect-server collection create --storage-gateway "\$GATEWAY_ID" --display-name "\$COLLECTION_NAME"

# Check the result
if [ \$? -eq 0 ]; then
  echo "Collection created successfully!"
else
  echo "Failed to create collection."
  exit 1
fi
EOF
            chmod +x /home/ubuntu/create-posix-collection.sh
            chown ubuntu:ubuntu /home/ubuntu/create-posix-collection.sh
            log "Created helper script for manually creating collections: /home/ubuntu/create-posix-collection.sh"
          else
            log "Could not extract gateway ID from output"
          fi
        else
          log "Failed to create POSIX gateway with exit code $GATEWAY_EXIT_CODE"
          echo "Failed to create POSIX gateway with exit code $GATEWAY_EXIT_CODE" > /home/ubuntu/POSIX_GATEWAY_FAILED.txt
          echo "Please check the output in posix-gateway-output.txt" >> /home/ubuntu/POSIX_GATEWAY_FAILED.txt
          echo "Command attempted: $GATEWAY_CMD" >> /home/ubuntu/POSIX_GATEWAY_FAILED.txt
        fi
      else
        log "POSIX gateway creation not requested (ENABLE_POSIX_GATEWAY=$ENABLE_POSIX_GATEWAY, POSIX_GATEWAY_NAME=$POSIX_GATEWAY_NAME)"
      fi
    else
      log "WARNING: Node setup failed with exit code $NODE_SETUP_EXIT_CODE"
      echo "Node setup failed with exit code $NODE_SETUP_EXIT_CODE" > /home/ubuntu/NODE_SETUP_FAILED.txt
      echo "Please examine node-setup-output.txt for details" >> /home/ubuntu/NODE_SETUP_FAILED.txt
      echo "You may need to run the node setup command manually:" >> /home/ubuntu/NODE_SETUP_FAILED.txt
      echo "sudo globus-connect-server node setup --ip-address $PUBLIC_IP" >> /home/ubuntu/NODE_SETUP_FAILED.txt
    fi
  fi
else
  log "Could not extract endpoint UUID from direct output"
  # Try to get endpoint details
  log "Attempting to retrieve endpoint details with endpoint show command..."
  ENDPOINT_SHOW=$(globus-connect-server endpoint show 2>&1)
  echo "$ENDPOINT_SHOW" > /home/ubuntu/endpoint-details.txt
  
  # Try to extract UUID from endpoint show output
  ENDPOINT_UUID=$(echo "$ENDPOINT_SHOW" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
  
  if [ -n "$ENDPOINT_UUID" ]; then
    log "Found endpoint UUID from show command: $ENDPOINT_UUID"
    echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
    echo "ENDPOINT_UUID=$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid-export.sh
    chmod +x /home/ubuntu/endpoint-uuid-export.sh
    export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
    echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" > /home/ubuntu/endpoint-url.txt
    
    log "Found a UUID, but skipped the original output parsing stage."
    log "Please run the node setup manually to complete the deployment:"
    log "sudo globus-connect-server node setup --ip-address YOUR_PUBLIC_IP"
    
    echo "Please run the node setup manually to complete the deployment:" > /home/ubuntu/MANUAL_NODE_SETUP.txt
    echo "sudo globus-connect-server node setup --ip-address YOUR_PUBLIC_IP" >> /home/ubuntu/MANUAL_NODE_SETUP.txt
  else
    log "WARNING: Could not extract endpoint UUID by any method"
    # Create a file to record this error
    echo "ERROR: Unable to extract endpoint UUID" > /home/ubuntu/MISSING_UUID.txt
    echo "Please examine endpoint-setup-output.txt manually to find the UUID" >> /home/ubuntu/MISSING_UUID.txt
    echo "Example of created endpoint line: 'Created endpoint 6695cdaf-818d-4a5d-b5fc-06e86c8a0a4b'" >> /home/ubuntu/MISSING_UUID.txt
  fi
fi

# Create a script to setup environment variables for Globus commands
cat > /home/ubuntu/globus-env.sh << 'EOF'
#!/bin/bash
# Helper script to set up Globus credentials environment variables

# Set client credentials
if [ -f /home/ubuntu/globus-client-id.txt ] && [ -f /home/ubuntu/globus-client-secret.txt ]; then
  export GCS_CLI_CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
  export GCS_CLI_CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
  echo "✓ Set GCS_CLI_CLIENT_ID and GCS_CLI_CLIENT_SECRET"
else
  echo "⚠️  Warning: Client credentials files not found"
fi

# Set endpoint ID
if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
  export GCS_CLI_ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt)
  echo "✓ Set GCS_CLI_ENDPOINT_ID to $(cat /home/ubuntu/endpoint-uuid.txt)"
else
  echo "⚠️  Warning: Endpoint UUID file not found"
fi

# Set node ID (for reference, not a standard environment variable)
if [ -f /home/ubuntu/node-id.txt ]; then
  export GLOBUS_NODE_ID=$(cat /home/ubuntu/node-id.txt)
  echo "✓ Set GLOBUS_NODE_ID to $(cat /home/ubuntu/node-id.txt)"
else
  echo "ℹ️  Node ID file not found (node may not be set up yet)"
fi

# Show what's been set
echo ""
echo "Environment variables set:"
echo "-------------------------"
echo "GCS_CLI_CLIENT_ID=${GCS_CLI_CLIENT_ID:0:8}..."
echo "GCS_CLI_CLIENT_SECRET=${GCS_CLI_CLIENT_SECRET:0:5}..."
[ -n "$GCS_CLI_ENDPOINT_ID" ] && echo "GCS_CLI_ENDPOINT_ID=$GCS_CLI_ENDPOINT_ID"
[ -n "$GLOBUS_NODE_ID" ] && echo "GLOBUS_NODE_ID=$GLOBUS_NODE_ID (for reference)"
echo ""
echo "You can now run globus-connect-server commands directly."
echo "Example: globus-connect-server endpoint show"
EOF

chmod +x /home/ubuntu/globus-env.sh
chown ubuntu:ubuntu /home/ubuntu/globus-env.sh

# Create a simple helper script to show endpoint details
cat > /home/ubuntu/show-endpoint.sh << 'EOF'
#!/bin/bash
# Helper script to show Globus endpoint details

# Source the credentials environment variables
source /home/ubuntu/globus-env.sh

# Check if we have UUID
if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
  export GCS_CLI_ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt)
  echo "Endpoint UUID: $GCS_CLI_ENDPOINT_ID"
  
  echo "===== Globus Connect Server Details ====="
  globus-connect-server endpoint show
  
  echo ""
  echo "===== Globus CLI Details ====="
  # Check if globus CLI is installed
  if command -v globus &> /dev/null; then
    globus endpoint show "$GCS_CLI_ENDPOINT_ID" || echo "Couldn't retrieve endpoint with Globus CLI"
  else
    echo "Globus CLI not found or not configured"
  fi
  
  echo ""
  echo "Access the endpoint at: https://app.globus.org/file-manager?origin_id=$GCS_CLI_ENDPOINT_ID"
else
  echo "No endpoint UUID found. Trying endpoint show command..."
  globus-connect-server endpoint show
fi
EOF

chmod +x /home/ubuntu/show-endpoint.sh
chown ubuntu:ubuntu /home/ubuntu/show-endpoint.sh

# Create a helper script with common Globus CLI commands
cat > /home/ubuntu/globus-cli-examples.sh << 'EOF'
#!/bin/bash
# Helper script with common Globus CLI commands

# Setup environment variables for Globus commands
source /home/ubuntu/globus-env.sh

# Get the endpoint UUID
ENDPOINT_UUID="$GCS_CLI_ENDPOINT_ID"

if [ -z "$ENDPOINT_UUID" ]; then
  echo "No endpoint UUID found. Make sure globus-env.sh properly sets the UUID."
  exit 1
fi

echo "===== Globus CLI Examples for Endpoint: $ENDPOINT_UUID ====="
echo ""
echo "1. Show endpoint details:"
echo "   globus endpoint show $ENDPOINT_UUID"
echo ""
echo "2. List endpoint's server components:"
echo "   globus endpoint server list $ENDPOINT_UUID"
echo ""
echo "3. List collections on this endpoint:"
echo "   globus endpoint collection list $ENDPOINT_UUID"
echo ""
echo "4. Search for other endpoints:"
echo "   globus endpoint search \"SEARCH_TERM\""
echo ""
echo "5. List your recent transfers:"
echo "   globus transfer task list"
echo ""
echo "6. Start a transfer using the CLI:"
echo "   globus transfer --dry-run $ENDPOINT_UUID:/path/to/source OTHER_ENDPOINT_UUID:/path/to/dest"
echo ""
echo "7. Manage endpoint permissions:"
echo "   globus endpoint permission list $ENDPOINT_UUID"
echo ""
echo "For more information, run: globus --help"
echo "or visit: https://docs.globus.org/cli/"
EOF

chmod +x /home/ubuntu/globus-cli-examples.sh
chown ubuntu:ubuntu /home/ubuntu/globus-cli-examples.sh

# Create deployment summary
NODE_SETUP_STATUS=$([ -f /home/ubuntu/node-setup-output.txt ] && echo "Completed" || echo "Not completed")
PUBLIC_IP=$(cat /home/ubuntu/public-ip.txt 2>/dev/null || echo "Not detected")
NODE_ID=$(cat /home/ubuntu/node-id.txt 2>/dev/null || echo "Not extracted")

# Determine which admin identity is being used
if [ -f /home/ubuntu/effective-collection-admin.txt ]; then
  EFFECTIVE_ADMIN=$(cat /home/ubuntu/effective-collection-admin.txt)
else
  EFFECTIVE_ADMIN="none specified"
fi

# Check if S3 gateway was created
S3_GATEWAY_STATUS="Not configured"
S3_GATEWAY_ID=""
S3_COLLECTION_STATUS="None"
S3_COLLECTION_ID=""
S3_COLLECTION_NAME=""
S3_COLLECTION_PERM_STATUS=""

if [ -f /home/ubuntu/s3-gateway-id.txt ]; then
  S3_GATEWAY_ID=$(cat /home/ubuntu/s3-gateway-id.txt)
  S3_GATEWAY_STATUS="Created - ID: $S3_GATEWAY_ID"
  
  if [ -f /home/ubuntu/s3-collection-id.txt ] && [ -f /home/ubuntu/s3-collection-name.txt ]; then
    S3_COLLECTION_ID=$(cat /home/ubuntu/s3-collection-id.txt)
    S3_COLLECTION_NAME=$(cat /home/ubuntu/s3-collection-name.txt)
    S3_COLLECTION_STATUS="Created - Name: $S3_COLLECTION_NAME, ID: $S3_COLLECTION_ID"
    
    if [ -f /home/ubuntu/s3-collection-permissions-set.txt ]; then
      S3_PERM_SET=$(cat /home/ubuntu/s3-collection-permissions-set.txt)
      if [ "$S3_PERM_SET" = "true" ]; then
        S3_COLLECTION_PERM_STATUS="Permissions granted to $EFFECTIVE_ADMIN"
      else
        if [ -f "/home/ubuntu/${S3_COLLECTION_NAME}_PERMISSION_FAILED.txt" ]; then
          S3_COLLECTION_PERM_STATUS="Failed to set permissions - See ${S3_COLLECTION_NAME}_PERMISSION_FAILED.txt"
        elif [ -z "$EFFECTIVE_ADMIN" ]; then
          S3_COLLECTION_PERM_STATUS="No admin identity specified - only service account has access"
        else
          S3_COLLECTION_PERM_STATUS="Unknown permission status"
        fi
      fi
    fi
  elif [ -f /home/ubuntu/S3_COLLECTION_FAILED.txt ]; then
    S3_COLLECTION_STATUS="Failed to create - See S3_COLLECTION_FAILED.txt"
  fi
fi

# Check if POSIX gateway was created
POSIX_GATEWAY_STATUS="Not configured"
POSIX_GATEWAY_ID=""
POSIX_COLLECTION_STATUS="None"
POSIX_COLLECTION_ID=""
POSIX_COLLECTION_NAME=""
POSIX_COLLECTION_PERM_STATUS=""

if [ -f /home/ubuntu/posix-gateway-id.txt ]; then
  POSIX_GATEWAY_ID=$(cat /home/ubuntu/posix-gateway-id.txt)
  POSIX_GATEWAY_STATUS="Created - ID: $POSIX_GATEWAY_ID"
  
  if [ -f /home/ubuntu/posix-collection-id.txt ] && [ -f /home/ubuntu/posix-collection-name.txt ]; then
    POSIX_COLLECTION_ID=$(cat /home/ubuntu/posix-collection-id.txt)
    POSIX_COLLECTION_NAME=$(cat /home/ubuntu/posix-collection-name.txt)
    POSIX_COLLECTION_STATUS="Created - Name: $POSIX_COLLECTION_NAME, ID: $POSIX_COLLECTION_ID"
    
    if [ -f /home/ubuntu/posix-collection-permissions-set.txt ]; then
      POSIX_PERM_SET=$(cat /home/ubuntu/posix-collection-permissions-set.txt)
      if [ "$POSIX_PERM_SET" = "true" ]; then
        POSIX_COLLECTION_PERM_STATUS="Permissions granted to $EFFECTIVE_ADMIN"
      else
        if [ -f "/home/ubuntu/${POSIX_COLLECTION_NAME}_PERMISSION_FAILED.txt" ]; then
          POSIX_COLLECTION_PERM_STATUS="Failed to set permissions - See ${POSIX_COLLECTION_NAME}_PERMISSION_FAILED.txt"
        elif [ -z "$EFFECTIVE_ADMIN" ]; then
          POSIX_COLLECTION_PERM_STATUS="No admin identity specified - only service account has access"
        else
          POSIX_COLLECTION_PERM_STATUS="Unknown permission status"
        fi
      fi
    fi
  elif [ -f /home/ubuntu/POSIX_COLLECTION_FAILED.txt ]; then
    POSIX_COLLECTION_STATUS="Failed to create - See POSIX_COLLECTION_FAILED.txt"
  fi
fi

# Check subscription status
SUBSCRIPTION_STATUS="Basic (unmanaged)"
if [ -f /home/ubuntu/SUBSCRIPTION_SUCCESS.txt ]; then
  SUBSCRIPTION_ID=$(cat /home/ubuntu/subscription-id.txt 2>/dev/null || echo "Unknown")
  SUBSCRIPTION_STATUS="Managed - ID: $SUBSCRIPTION_ID"
elif [ -f /home/ubuntu/SUBSCRIPTION_FAILED.txt ]; then
  SUBSCRIPTION_STATUS="Failed to set subscription - See SUBSCRIPTION_FAILED.txt"
elif [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
  SUBSCRIPTION_STATUS="Attempted to set subscription ID: $GLOBUS_SUBSCRIPTION_ID (status unknown)"
fi

cat > /home/ubuntu/deployment-summary.txt << EOF
=== Globus Connect Server Deployment Summary ===
Deployment completed: $(date)

Endpoint Details:
- Display Name: $GLOBUS_DISPLAY_NAME
- Owner: $GLOBUS_OWNER
- Organization: $GLOBUS_ORGANIZATION
- Contact Email: $GLOBUS_CONTACT_EMAIL
- UUID: ${ENDPOINT_UUID:-Not available}
- Domain Name: ${DOMAIN_NAME:-Not available}

Node Setup:
- Status: $NODE_SETUP_STATUS
- Public IP: $PUBLIC_IP
- Node ID: $NODE_ID
- Node Details: $([ -f /home/ubuntu/node-details.txt ] && echo "Available in /home/ubuntu/node-details.txt" || echo "Not available")
- Node Command: sudo globus-connect-server node setup --ip-address $PUBLIC_IP
- Node List Command: globus-connect-server node list

Subscription Status:
- Status: $SUBSCRIPTION_STATUS

Collection Access:
- Admin Identity: ${EFFECTIVE_ADMIN:-None specified}
  $([ -z "$EFFECTIVE_ADMIN" ] && echo "  WARNING: No admin identity specified. Only the service account ($GLOBUS_OWNER) will have access." || echo "")

Storage Gateways:
- S3 Gateway: $S3_GATEWAY_STATUS
  $([ -n "$S3_BUCKET_NAME" ] && echo "  S3 Bucket: $S3_BUCKET_NAME" || echo "")
  $([ -f /home/ubuntu/s3-gateway-id.txt ] && echo "  Gateway ID: $(cat /home/ubuntu/s3-gateway-id.txt)" || echo "")
  Collection: $S3_COLLECTION_STATUS
  $([ -n "$S3_COLLECTION_PERM_STATUS" ] && echo "  Permissions: $S3_COLLECTION_PERM_STATUS" || echo "")
  
- POSIX Gateway: $POSIX_GATEWAY_STATUS
  $([ -f /home/ubuntu/posix-gateway-id.txt ] && echo "  Gateway ID: $(cat /home/ubuntu/posix-gateway-id.txt)" || echo "")
  Collection: $POSIX_COLLECTION_STATUS
  $([ -n "$POSIX_COLLECTION_PERM_STATUS" ] && echo "  Permissions: $POSIX_COLLECTION_PERM_STATUS" || echo "")

Access Information:
- Endpoint URL: https://app.globus.org/file-manager?origin_id=${ENDPOINT_UUID:-MISSING_UUID}

Helper Scripts:
- /home/ubuntu/globus-env.sh: Setup Globus credentials environment variables 
- /home/ubuntu/show-endpoint.sh: Show endpoint details
- /home/ubuntu/globus-cli-examples.sh: Examples of common Globus CLI commands
$([ -f /home/ubuntu/create-posix-collection.sh ] && echo "- /home/ubuntu/create-posix-collection.sh: Create collections for POSIX gateway" || echo "")
$([ -f /home/ubuntu/create-s3-collection.sh ] && echo "- /home/ubuntu/create-s3-collection.sh: Create collections for S3 gateway" || echo "")

To run Globus commands manually:
$ source /home/ubuntu/globus-env.sh
$ globus-connect-server endpoint show

Service Status:
- Apache2: $(systemctl is-active apache2 2>/dev/null || echo "Unknown")
- GridFTP: $(systemctl is-active globus-gridftp-server 2>/dev/null || echo "Unknown")
EOF

# Set permissions for all files
# Make sure files exist first to avoid errors
for f in $(find /home/ubuntu -type f); do
  chown ubuntu:ubuntu "$f"
done

# Set restrictive permissions on credential files
if [ -f /home/ubuntu/globus-client-id.txt ]; then
  chmod 600 /home/ubuntu/globus-client-id.txt
fi

if [ -f /home/ubuntu/globus-client-secret.txt ]; then
  chmod 600 /home/ubuntu/globus-client-secret.txt
fi

# Make scripts executable
for f in $(find /home/ubuntu -name "*.sh"); do
  chmod +x "$f"
  chown ubuntu:ubuntu "$f"
done

# Verify permissions were set correctly
log "Verifying file ownership..."
ls -la /home/ubuntu/ > /home/ubuntu/file-permissions.txt
chown ubuntu:ubuntu /home/ubuntu/file-permissions.txt

# Create a diagnostic file with sanitized environment variables for debugging
debug_log "Creating diagnostic file with environment information"
cat > /home/ubuntu/environment-diagnostics.txt << EOF
=== Globus Connect Server Deployment Diagnostics ===
Generated: $(date)

Environment Variables (sensitive values partially redacted):
- GLOBUS_CLIENT_ID: ${GLOBUS_CLIENT_ID:0:8}... (truncated)
- GLOBUS_CLIENT_SECRET: ${GLOBUS_CLIENT_SECRET:0:3}... (truncated) 
- GLOBUS_DISPLAY_NAME: $GLOBUS_DISPLAY_NAME
- GLOBUS_ORGANIZATION: $GLOBUS_ORGANIZATION
- GLOBUS_OWNER: $GLOBUS_OWNER
- GLOBUS_CONTACT_EMAIL: $GLOBUS_CONTACT_EMAIL
- GLOBUS_PROJECT_ID: ${GLOBUS_PROJECT_ID:0:8}... (truncated)
- GLOBUS_SUBSCRIPTION_ID: $GLOBUS_SUBSCRIPTION_ID
- ENABLE_S3_CONNECTOR: $ENABLE_S3_CONNECTOR
- S3_BUCKET_NAME: $S3_BUCKET_NAME
- ENABLE_POSIX_GATEWAY: $ENABLE_POSIX_GATEWAY
- POSIX_GATEWAY_NAME: $POSIX_GATEWAY_NAME
- PRESERVE_INSTANCE: $PRESERVE_INSTANCE
- COLLECTION_ADMIN: $COLLECTION_ADMIN

CLI Environment Variables:
- GCS_CLI_CLIENT_ID: ${GCS_CLI_CLIENT_ID:0:8}... (truncated)
- GCS_CLI_CLIENT_SECRET: ${GCS_CLI_CLIENT_SECRET:0:3}... (truncated)
- GCS_CLI_ENDPOINT_ID: $GCS_CLI_ENDPOINT_ID

Command Line Check:
- globus-connect-server location: $(which globus-connect-server 2>/dev/null || echo "NOT FOUND")
- globus-cli location: $(which globus 2>/dev/null || echo "NOT FOUND")

Major Component Status:
- Endpoint created: $([ -n "$ENDPOINT_UUID" ] && echo "YES - $ENDPOINT_UUID" || echo "NO")
- Subscription set: $([ -f /home/ubuntu/SUBSCRIPTION_SUCCESS.txt ] && echo "YES" || echo "NO")
- S3 Gateway created: $([ -f /home/ubuntu/s3-gateway-id.txt ] && echo "YES - $(cat /home/ubuntu/s3-gateway-id.txt)" || echo "NO")
- S3 Collection created: $([ -f /home/ubuntu/s3-collection-id.txt ] && echo "YES - $(cat /home/ubuntu/s3-collection-id.txt)" || echo "NO")
- POSIX Gateway created: $([ -f /home/ubuntu/posix-gateway-id.txt ] && echo "YES - $(cat /home/ubuntu/posix-gateway-id.txt)" || echo "NO")
- Node setup completed: $([ -f /home/ubuntu/node-setup-output.txt ] && echo "YES" || echo "NO")

For detailed logs, check:
- /var/log/globus-setup.log
- /home/ubuntu/debug.log (detailed debug messages)
- /home/ubuntu/s3-gateway-output.txt (if S3 connector was attempted)
- /home/ubuntu/subscription-update-output.txt (if subscription was set)
EOF

# Set proper permissions
chmod 600 /home/ubuntu/environment-diagnostics.txt
chown ubuntu:ubuntu /home/ubuntu/environment-diagnostics.txt

log "=== Globus Connect Server setup completed: $(date) ==="
debug_log "SETUP COMPLETED"
exit 0