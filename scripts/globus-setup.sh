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

# Make sure /home/ubuntu exists and is writable
mkdir -p /home/ubuntu 2>/dev/null || true
chmod 755 /home/ubuntu 2>/dev/null || true

log "=== Starting Simplified Globus Connect Server setup: $(date) ==="
debug_log "Starting setup with UID=$(id -u), EUID=$(id -eu), USER=$USER"

# Log debug information about environment variables
debug_log "Starting with environment variables:"
debug_log "GLOBUS_BASE_NAME=$GLOBUS_BASE_NAME"
debug_log "GLOBUS_DISPLAY_NAME=$GLOBUS_DISPLAY_NAME"
debug_log "GLOBUS_ORGANIZATION=$GLOBUS_ORGANIZATION"
debug_log "GLOBUS_OWNER=$GLOBUS_OWNER"
debug_log "GLOBUS_CONTACT_EMAIL=$GLOBUS_CONTACT_EMAIL"
debug_log "GLOBUS_PROJECT_ID=${GLOBUS_PROJECT_ID:0:5}..." # Truncating for security
debug_log "S3 gateway will be created with subscription ID"
debug_log "GLOBUS_SUBSCRIPTION_ID=$GLOBUS_SUBSCRIPTION_ID"
debug_log "PRESERVE_INSTANCE=$PRESERVE_INSTANCE"
debug_log "REMOVE_SERVICE_ACCOUNT_ROLE=$REMOVE_SERVICE_ACCOUNT_ROLE"

# Verify that subscription ID is set for S3 gateway
if [ -z "$GLOBUS_SUBSCRIPTION_ID" ]; then
  debug_log "ERROR: GLOBUS_SUBSCRIPTION_ID is empty - required for S3 gateway"
  echo "ERROR: GLOBUS_SUBSCRIPTION_ID parameter is required" > /home/ubuntu/S3_PARAMETER_ERROR.txt
else
  debug_log "GLOBUS_SUBSCRIPTION_ID is set to: $GLOBUS_SUBSCRIPTION_ID"
fi

# Install dependencies for setup and checks
log "Installing dependencies..."
apt-get update
apt-get install -y curl wget apt-transport-https ca-certificates python3-pip jq

# Install Globus Connect Server first (required for the checks to work)
log "Installing Globus Connect Server packages..."
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

# Function to check if service account is a project admin using simple command-line approach
check_project_admin() {
  log "Checking if service account has admin privileges for project $GLOBUS_PROJECT_ID..."
  debug_log "Using globus-connect-server command to check admin status"

  # Use globus-connect-server role list to check admin status
  # Instead of complex API calls, we just check if roles can be listed
  # which is only possible with proper admin permissions
  ROLES_OUTPUT=$(globus-connect-server role list 2>&1)
  ROLES_EXIT_CODE=$?
  
  # Save output for debugging
  echo "$ROLES_OUTPUT" > /home/ubuntu/role-list-check.txt
  
  if [ $ROLES_EXIT_CODE -eq 0 ]; then
    log "Service account has admin privileges - check passed"
    debug_log "Project admin check passed"
    return 0
  else
    log "ERROR: Service account does not have admin privileges"
    echo "Service account (Client ID: $GLOBUS_CLIENT_ID) does not have proper admin privileges" > /home/ubuntu/PROJECT_ADMIN_ERROR.txt
    echo "The service account must have admin privileges to deploy Globus Connect Server." >> /home/ubuntu/PROJECT_ADMIN_ERROR.txt
    echo "Please ensure your service account has admin privileges in your Globus Project." >> /home/ubuntu/PROJECT_ADMIN_ERROR.txt
    return 1
  fi
}

# Function to check if service account is subscription admin using simple command
check_subscription_admin() {
  log "Checking if service account has privileges for subscription $GLOBUS_SUBSCRIPTION_ID..."
  debug_log "Using globus-connect-server endpoint show to verify permissions"

  # Use endpoint show command to verify we have proper permissions
  # This is much simpler than making API calls directly
  ENDPOINT_SHOW=$(globus-connect-server endpoint show 2>&1)
  ENDPOINT_SHOW_EXIT_CODE=$?
  
  # Save output for debugging
  echo "$ENDPOINT_SHOW" > /home/ubuntu/endpoint-show-check.txt
  
  if [ $ENDPOINT_SHOW_EXIT_CODE -eq 0 ]; then
    log "Service account has subscription privileges - check passed"
    debug_log "Subscription admin check passed"
    return 0
  else
    log "ERROR: Service account does not have subscription admin privileges"
    echo "Service account (Client ID: $GLOBUS_CLIENT_ID) does not have admin privileges for subscription $GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/SUBSCRIPTION_ADMIN_ERROR.txt
    echo "The service account must have proper permissions to deploy Globus Connect Server with S3 connector." >> /home/ubuntu/SUBSCRIPTION_ADMIN_ERROR.txt
    echo "Please ensure your service account has admin privileges in your subscription group." >> /home/ubuntu/SUBSCRIPTION_ADMIN_ERROR.txt
    return 1
  fi
}

# Run permission checks
if [ -n "$GLOBUS_PROJECT_ID" ]; then
  if ! check_project_admin; then
    log "ERROR: Service account is not a project admin. Deployment cannot continue."
    echo "Deployment failed: Service account is not a project admin." > /home/ubuntu/PERMISSION_CHECK_FAILED.txt
    echo "Please see PROJECT_ADMIN_ERROR.txt for details." >> /home/ubuntu/PERMISSION_CHECK_FAILED.txt
    exit 1
  fi
else
  log "WARNING: GLOBUS_PROJECT_ID not provided, skipping project admin check"
  debug_log "Project admin check skipped due to missing GLOBUS_PROJECT_ID"
fi

if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
  if ! check_subscription_admin; then
    log "ERROR: Service account is not a subscription admin. Deployment cannot continue."
    echo "Deployment failed: Service account is not a subscription admin." > /home/ubuntu/PERMISSION_CHECK_FAILED.txt
    echo "Please see SUBSCRIPTION_ADMIN_ERROR.txt for details." >> /home/ubuntu/PERMISSION_CHECK_FAILED.txt
    exit 1
  fi
else
  log "WARNING: GLOBUS_SUBSCRIPTION_ID not provided, skipping subscription admin check"
  debug_log "Subscription admin check skipped due to missing GLOBUS_SUBSCRIPTION_ID"
fi

log "Permission checks completed successfully. Proceeding with installation."

# GCS is already installed and version checked above

# Save environment variables to files in Ubuntu home
mkdir -p /home/ubuntu
chmod 755 /home/ubuntu

# Save environment variables ensuring we don't create empty files
[ -n "$GLOBUS_CLIENT_ID" ] && echo "$GLOBUS_CLIENT_ID" > /home/ubuntu/globus-client-id.txt || echo "MISSING" > /home/ubuntu/globus-client-id.txt
[ -n "$GLOBUS_CLIENT_SECRET" ] && echo "$GLOBUS_CLIENT_SECRET" > /home/ubuntu/globus-client-secret.txt || echo "MISSING" > /home/ubuntu/globus-client-secret.txt
[ -n "$GLOBUS_BASE_NAME" ] && echo "$GLOBUS_BASE_NAME" > /home/ubuntu/globus-base-name.txt || echo "MISSING" > /home/ubuntu/globus-base-name.txt
[ -n "$GLOBUS_DISPLAY_NAME" ] && echo "$GLOBUS_DISPLAY_NAME" > /home/ubuntu/globus-display-name.txt || echo "MISSING" > /home/ubuntu/globus-display-name.txt
[ -n "$GLOBUS_ORGANIZATION" ] && echo "$GLOBUS_ORGANIZATION" > /home/ubuntu/globus-organization.txt || echo "MISSING" > /home/ubuntu/globus-organization.txt
[ -n "$GLOBUS_OWNER" ] && echo "$GLOBUS_OWNER" > /home/ubuntu/globus-owner.txt || echo "MISSING" > /home/ubuntu/globus-owner.txt
[ -n "$GLOBUS_CONTACT_EMAIL" ] && echo "$GLOBUS_CONTACT_EMAIL" > /home/ubuntu/globus-contact-email.txt || echo "MISSING" > /home/ubuntu/globus-contact-email.txt
[ -n "$GLOBUS_PROJECT_ID" ] && echo "$GLOBUS_PROJECT_ID" > /home/ubuntu/globus-project-id.txt || echo "MISSING" > /home/ubuntu/globus-project-id.txt

# Save subscription and S3 gateway information
[ -n "$GLOBUS_SUBSCRIPTION_ID" ] && echo "$GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/subscription-id.txt || echo "NONE" > /home/ubuntu/subscription-id.txt
[ -n "$S3_GATEWAY_DISPLAY_NAME" ] && echo "$S3_GATEWAY_DISPLAY_NAME" > /home/ubuntu/s3-gateway-display-name.txt || echo "$GLOBUS_BASE_NAME S3 Gateway" > /home/ubuntu/s3-gateway-display-name.txt

# Save owner configuration
[ -n "$REMOVE_SERVICE_ACCOUNT_ROLE" ] && echo "$REMOVE_SERVICE_ACCOUNT_ROLE" > /home/ubuntu/remove-service-account-role.txt || echo "false" > /home/ubuntu/remove-service-account-role.txt

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

# Extract endpoint UUID from output, looking specifically for the "Created endpoint" pattern
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
  
  # Save subscription ID to file for reference if provided
  if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
    echo "$GLOBUS_SUBSCRIPTION_ID" > /home/ubuntu/subscription-id.txt
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
      
      # Now that node setup is complete, we can update the subscription if provided
      if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
        log "Associating endpoint with subscription ID: $GLOBUS_SUBSCRIPTION_ID"
        debug_log "Setting up subscription with ID: $GLOBUS_SUBSCRIPTION_ID after node setup"
        
        # Create a helper script to set the subscription later if it fails now
        cat > /home/ubuntu/set-subscription.sh << 'EOFSUBSCRIPTION'
#!/bin/bash
# Script to set subscription ID on the endpoint

# Load environment variables
if [ -f /home/ubuntu/setup-env.sh ]; then
  source /home/ubuntu/setup-env.sh
fi

# Get subscription ID
SUBSCRIPTION_ID="$(cat /home/ubuntu/subscription-id.txt 2>/dev/null)"
if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Error: No subscription ID found in /home/ubuntu/subscription-id.txt"
  exit 1
fi

echo "Setting subscription ID: $SUBSCRIPTION_ID"
globus-connect-server endpoint update --subscription-id "$SUBSCRIPTION_ID"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "Successfully set subscription ID"
  echo "Endpoint is now managed under subscription ID: $SUBSCRIPTION_ID" > /home/ubuntu/SUBSCRIPTION_SUCCESS.txt
else
  echo "Failed to set subscription ID with exit code: $EXIT_CODE"
fi
EOFSUBSCRIPTION
        chmod +x /home/ubuntu/set-subscription.sh
        chown ubuntu:ubuntu /home/ubuntu/set-subscription.sh
        
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
          echo "/home/ubuntu/set-subscription.sh" >> /home/ubuntu/SUBSCRIPTION_FAILED.txt
        fi
      fi
      
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

      # Check if subscription is set for S3 gateway
      if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
        log "Creating S3 storage gateway"
        debug_log "S3 Connector Variables: GLOBUS_SUBSCRIPTION_ID=$GLOBUS_SUBSCRIPTION_ID"
        
        # Get S3 gateway display name
        S3_GATEWAY_DISPLAY_NAME_VALUE="$(cat /home/ubuntu/s3-gateway-display-name.txt)"
        
        # Set S3 command parameters - simplified to just use AWS credentials
        S3_CMD="globus-connect-server storage-gateway create s3 --s3-endpoint https://s3.amazonaws.com --s3-user-credential"
        
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
            
            # Automatically create a collection for this gateway
            log "S3 gateway created successfully. Automatically creating a collection..."
            S3_COLLECTION_NAME="${GLOBUS_BASE_NAME} S3 Collection"
            log "Creating collection: $S3_COLLECTION_NAME for gateway $S3_GATEWAY_ID"
            
            COLLECTION_OUTPUT=$(globus-connect-server collection create --storage-gateway "$S3_GATEWAY_ID" --display-name "$S3_COLLECTION_NAME" 2>&1)
            COLLECTION_EXIT_CODE=$?
            
            # Save output for reference
            echo "$COLLECTION_OUTPUT" > /home/ubuntu/s3-collection-output.txt
            
            if [ $COLLECTION_EXIT_CODE -eq 0 ]; then
              log "S3 collection created successfully"
              
              # Extract the collection ID from the output
              S3_COLLECTION_ID=$(echo "$COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
              if [ -n "$S3_COLLECTION_ID" ]; then
                log "Extracted S3 collection ID: $S3_COLLECTION_ID"
                echo "$S3_COLLECTION_ID" > /home/ubuntu/s3-collection-id.txt
                
                # Create reference to the collection URL
                COLLECTION_URL="https://app.globus.org/file-manager?destination_id=${S3_COLLECTION_ID}"
                echo "$COLLECTION_URL" > /home/ubuntu/s3-collection-url.txt
                
                # Add permissions for the owner if specified
                if [ -n "$GLOBUS_OWNER" ]; then
                  log "Setting permissions for owner $GLOBUS_OWNER on collection $S3_COLLECTION_ID"
                  PERMISSION_OUTPUT=$(globus-connect-server endpoint permission create --identity "$GLOBUS_OWNER" --permissions rw --collection "$S3_COLLECTION_ID" 2>&1)
                  PERMISSION_EXIT_CODE=$?
                  
                  # Save output for reference
                  echo "$PERMISSION_OUTPUT" > /home/ubuntu/s3-permission-output.txt
                  
                  if [ $PERMISSION_EXIT_CODE -eq 0 ]; then
                    log "Successfully set permissions for $GLOBUS_OWNER on S3 collection"
                    echo "true" > /home/ubuntu/s3-permissions-set.txt
                  else
                    log "Failed to set permissions for $GLOBUS_OWNER on S3 collection with exit code $PERMISSION_EXIT_CODE"
                    echo "false" > /home/ubuntu/s3-permissions-set.txt
                    echo "Error details: $PERMISSION_OUTPUT" >> /home/ubuntu/S3_PERMISSION_FAILED.txt
                  fi
                fi
              else
                log "Could not extract collection ID from output"
              fi
            else
              log "Failed to create S3 collection with exit code $COLLECTION_EXIT_CODE"
              echo "Failed to create S3 collection with exit code $COLLECTION_EXIT_CODE" > /home/ubuntu/S3_COLLECTION_FAILED.txt
              echo "Command output: $COLLECTION_OUTPUT" >> /home/ubuntu/S3_COLLECTION_FAILED.txt
            fi
            
            # Still create a summary file with access information
            cat > /home/ubuntu/s3-collection-info.txt << EOF
S3 Gateway and Collection Information:
======================================
Gateway ID: $S3_GATEWAY_ID
Collection ID: ${S3_COLLECTION_ID:-Failed to create}
Collection Name: $S3_COLLECTION_NAME
Access URL: ${COLLECTION_URL:-Not available}
Owner Permissions: $([ -f /home/ubuntu/s3-permissions-set.txt ] && cat /home/ubuntu/s3-permissions-set.txt || echo "Not set")

You can access this collection through the Globus web interface at:
https://app.globus.org/file-manager
EOF
            chown ubuntu:ubuntu /home/ubuntu/s3-collection-info.txt
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
        fi
      else
        if [ -z "$GLOBUS_SUBSCRIPTION_ID" ]; then
          log "S3 gateway creation failed: GLOBUS_SUBSCRIPTION_ID not provided (required for S3 connector)"
          echo "ERROR: S3 gateway creation failed - no subscription ID provided" > /home/ubuntu/S3_MISSING_SUBSCRIPTION.txt
          echo "The S3 connector requires a Globus subscription" >> /home/ubuntu/S3_MISSING_SUBSCRIPTION.txt
        fi
      fi
      
      # POSIX gateway support removed to focus on S3 connectivity
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

# Check if S3 gateway was created
S3_GATEWAY_STATUS="Not configured"
S3_GATEWAY_ID=""
S3_COLLECTION_ID=""
S3_COLLECTION_URL=""

if [ -f /home/ubuntu/s3-gateway-id.txt ]; then
  S3_GATEWAY_ID=$(cat /home/ubuntu/s3-gateway-id.txt)
  S3_GATEWAY_STATUS="Created - ID: $S3_GATEWAY_ID"
  
  # Check if collection was created
  if [ -f /home/ubuntu/s3-collection-id.txt ]; then
    S3_COLLECTION_ID=$(cat /home/ubuntu/s3-collection-id.txt)
    S3_COLLECTION_STATUS="Created - ID: $S3_COLLECTION_ID"
    
    # Check if we have a URL
    if [ -f /home/ubuntu/s3-collection-url.txt ]; then
      S3_COLLECTION_URL=$(cat /home/ubuntu/s3-collection-url.txt)
    fi
    
    # Check if permissions were set
    if [ -f /home/ubuntu/s3-permissions-set.txt ] && [ "$(cat /home/ubuntu/s3-permissions-set.txt)" = "true" ]; then
      S3_PERMISSIONS_STATUS="Permissions granted to $GLOBUS_OWNER"
    else
      S3_PERMISSIONS_STATUS="No permissions set or permission setting failed"
    fi
  else
    S3_COLLECTION_STATUS="Failed to create collection"
  fi
else
  S3_COLLECTION_STATUS="No gateway created"
fi

# POSIX gateway support removed to focus on S3 connectivity

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
- Service Account Role: $([ "$REMOVE_SERVICE_ACCOUNT_ROLE" = "true" ] && echo "Will be removed" || echo "Kept")

Permission Checks:
- Project Admin: $([ -n "$GLOBUS_PROJECT_ID" ] && echo "Passed - Service account is admin in project" || echo "Skipped - No project ID provided")
- Subscription Admin: $([ -n "$GLOBUS_SUBSCRIPTION_ID" ] && echo "Passed - Service account is admin in subscription group" || echo "Skipped - No subscription ID provided")

Node Setup:
- Status: $NODE_SETUP_STATUS
- Public IP: $PUBLIC_IP
- Node ID: $NODE_ID
- Node Details: $([ -f /home/ubuntu/node-details.txt ] && echo "Available in /home/ubuntu/node-details.txt" || echo "Not available")
- Node Command: sudo globus-connect-server node setup --ip-address $PUBLIC_IP
- Node List Command: globus-connect-server node list

Subscription Status:
- Status: $SUBSCRIPTION_STATUS

S3 Gateway and Collection:
- Gateway: $S3_GATEWAY_STATUS
  $([ -f /home/ubuntu/s3-gateway-id.txt ] && echo "  Gateway ID: $(cat /home/ubuntu/s3-gateway-id.txt)" || echo "")
  $([ -n "$S3_COLLECTION_STATUS" ] && echo "  Collection: $S3_COLLECTION_STATUS" || echo "")
  $([ -n "$S3_COLLECTION_ID" ] && echo "  Collection ID: $S3_COLLECTION_ID" || echo "")
  $([ -n "$S3_PERMISSIONS_STATUS" ] && echo "  Permissions: $S3_PERMISSIONS_STATUS" || echo "")
  $([ -n "$S3_COLLECTION_URL" ] && echo "  Access URL: $S3_COLLECTION_URL" || echo "")

Access Information:
- Endpoint URL: https://app.globus.org/file-manager?origin_id=${ENDPOINT_UUID:-MISSING_UUID}

Helper Scripts:
- /home/ubuntu/globus-env.sh: Setup Globus credentials environment variables 
- /home/ubuntu/show-endpoint.sh: Show endpoint details
- /home/ubuntu/globus-cli-examples.sh: Examples of common Globus CLI commands

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
- GLOBUS_BASE_NAME: $GLOBUS_BASE_NAME
- GLOBUS_DISPLAY_NAME: $GLOBUS_DISPLAY_NAME
- GLOBUS_ORGANIZATION: $GLOBUS_ORGANIZATION
- GLOBUS_OWNER: $GLOBUS_OWNER
- GLOBUS_CONTACT_EMAIL: $GLOBUS_CONTACT_EMAIL
- GLOBUS_PROJECT_ID: ${GLOBUS_PROJECT_ID:0:8}... (truncated)
- GLOBUS_SUBSCRIPTION_ID: $GLOBUS_SUBSCRIPTION_ID
- S3 Gateway: Enabled with subscription
# POSIX gateway support removed to focus on S3 connectivity
- PRESERVE_INSTANCE: $PRESERVE_INSTANCE
- REMOVE_SERVICE_ACCOUNT_ROLE: $REMOVE_SERVICE_ACCOUNT_ROLE

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
# POSIX gateway support removed to focus on S3 connectivity
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

# Set the endpoint owner if requested
if [ "$RESET_ENDPOINT_OWNER" = "true" ] && [ -n "$ENDPOINT_UUID" ] && [ -n "$GLOBUS_OWNER" ]; then
  log "Setting up endpoint ownership for: $GLOBUS_OWNER"
  
  # STEP 1: IMPORTANT - MUST set owner-string FIRST while service identity still has permissions
  log "Setting advertised owner string to: $GLOBUS_OWNER"
  OWNER_STRING_CMD="globus-connect-server endpoint set-owner-string \"$GLOBUS_OWNER\""
  log "Running command to set owner string: $OWNER_STRING_CMD"
  
  # Execute the command to set owner string
  OWNER_STRING_OUTPUT=$(eval $OWNER_STRING_CMD 2>&1)
  OWNER_STRING_EXIT_CODE=$?
  
  # Save output for reference
  echo "$OWNER_STRING_OUTPUT" > /home/ubuntu/endpoint-set-owner-string.txt
  
  if [ $OWNER_STRING_EXIT_CODE -eq 0 ]; then
    log "Successfully set advertised owner string to $GLOBUS_OWNER"
    echo "Successfully set advertised owner string to $GLOBUS_OWNER" > /home/ubuntu/OWNER_STRING_SUCCESS.txt
    
    # STEP 2: Now set the actual owner (must be done AFTER setting owner-string)
    OWNER_SET_CMD="globus-connect-server endpoint set-owner \"$GLOBUS_OWNER\""
    log "Running command to set owner: $OWNER_SET_CMD"
    
    # Execute the command to set owner
    OWNER_SET_OUTPUT=$(eval $OWNER_SET_CMD 2>&1)
    OWNER_SET_EXIT_CODE=$?
    
    # Save output for reference
    echo "$OWNER_SET_OUTPUT" > /home/ubuntu/endpoint-set-owner.txt
    
    if [ $OWNER_SET_EXIT_CODE -eq 0 ]; then
      log "Successfully set endpoint owner to $GLOBUS_OWNER"
      echo "Successfully set endpoint owner to $GLOBUS_OWNER" > /home/ubuntu/OWNER_SET_SUCCESS.txt
      
      # Overall success
      echo "Successfully updated both owner-string and owner to $GLOBUS_OWNER" > /home/ubuntu/OWNER_RESET_SUCCESS.txt
    else
      log "Failed to set endpoint owner with exit code $OWNER_SET_EXIT_CODE"
      echo "Failed to set endpoint owner with exit code $OWNER_SET_EXIT_CODE" > /home/ubuntu/OWNER_SET_FAILED.txt
      echo "Command: $OWNER_SET_CMD" >> /home/ubuntu/OWNER_SET_FAILED.txt
      echo "Output: $OWNER_SET_OUTPUT" >> /home/ubuntu/OWNER_SET_FAILED.txt
      
      # Partial success
      echo "WARNING: Set owner-string but failed to set owner" > /home/ubuntu/OWNER_RESET_PARTIAL.txt
    fi
  else
    log "Failed to set advertised owner string with exit code $OWNER_STRING_EXIT_CODE"
    echo "Failed to set advertised owner string with exit code $OWNER_STRING_EXIT_CODE" > /home/ubuntu/OWNER_STRING_FAILED.txt
    echo "Command: $OWNER_STRING_CMD" >> /home/ubuntu/OWNER_STRING_FAILED.txt
    echo "Output: $OWNER_STRING_OUTPUT" >> /home/ubuntu/OWNER_STRING_FAILED.txt
    
    # Overall failure - don't even try to set owner if owner-string fails
    echo "Failed to set advertised owner string, not attempting to set owner" > /home/ubuntu/OWNER_RESET_FAILED.txt
  fi
else
  if [ "$RESET_ENDPOINT_OWNER" != "true" ]; then
    log "Endpoint owner reset not requested (RESET_ENDPOINT_OWNER=$RESET_ENDPOINT_OWNER)"
    echo "Endpoint owner reset not requested (RESET_ENDPOINT_OWNER=$RESET_ENDPOINT_OWNER)" > /home/ubuntu/OWNER_RESET_DISABLED.txt
  elif [ -z "$ENDPOINT_UUID" ]; then
    log "Cannot reset endpoint owner - no endpoint UUID available"
    echo "Cannot reset endpoint owner - no endpoint UUID available" > /home/ubuntu/OWNER_RESET_FAILED.txt
  elif [ -z "$GLOBUS_OWNER" ]; then
    log "Cannot reset endpoint owner - GLOBUS_OWNER not specified"
    echo "Cannot reset endpoint owner - GLOBUS_OWNER not specified" > /home/ubuntu/OWNER_RESET_FAILED.txt
  fi
fi

# Handle removing service account role if requested
if [ "$REMOVE_SERVICE_ACCOUNT_ROLE" = "true" ] && [ -n "$ENDPOINT_UUID" ] && [ -n "$GLOBUS_OWNER" ]; then
  log "RemoveServiceAccountRole is enabled, will attempt to remove service account role"
  
  # First, need to find the service account
  log "Checking for service account roles..."
  ROLES_OUTPUT=$(globus-connect-server role list 2>&1)
  echo "$ROLES_OUTPUT" > /home/ubuntu/role-list-output.txt
  
  # Look for a role with the "service" type
  SERVICE_ROLE_ID=$(echo "$ROLES_OUTPUT" | grep -i "service" | awk '{print $1}' | head -1)
  
  if [ -n "$SERVICE_ROLE_ID" ]; then
    log "Found service role with ID: $SERVICE_ROLE_ID"
    echo "$SERVICE_ROLE_ID" > /home/ubuntu/service-role-id.txt
    
    # Remove the service role
    log "Removing service role: $SERVICE_ROLE_ID"
    REMOVE_ROLE_CMD="globus-connect-server role delete $SERVICE_ROLE_ID"
    REMOVE_ROLE_OUTPUT=$(eval $REMOVE_ROLE_CMD 2>&1)
    REMOVE_ROLE_EXIT_CODE=$?
    
    # Save output for reference
    echo "$REMOVE_ROLE_OUTPUT" > /home/ubuntu/remove-service-role-output.txt
    
    if [ $REMOVE_ROLE_EXIT_CODE -eq 0 ]; then
      log "Successfully removed service role"
      echo "Successfully removed service role with ID: $SERVICE_ROLE_ID" > /home/ubuntu/SERVICE_ROLE_REMOVED.txt
    else
      log "Failed to remove service role with exit code $REMOVE_ROLE_EXIT_CODE"
      echo "Failed to remove service role with exit code $REMOVE_ROLE_EXIT_CODE" > /home/ubuntu/SERVICE_ROLE_REMOVE_FAILED.txt
      echo "Command: $REMOVE_ROLE_CMD" >> /home/ubuntu/SERVICE_ROLE_REMOVE_FAILED.txt
      echo "Output: $REMOVE_ROLE_OUTPUT" >> /home/ubuntu/SERVICE_ROLE_REMOVE_FAILED.txt
    fi
  else
    log "No service role found to remove"
    echo "No service role found to remove" > /home/ubuntu/NO_SERVICE_ROLE.txt
  fi
else
  if [ "$REMOVE_SERVICE_ACCOUNT_ROLE" != "true" ]; then
    log "Service role removal not requested (REMOVE_SERVICE_ACCOUNT_ROLE=$REMOVE_SERVICE_ACCOUNT_ROLE)"
  fi
fi

log "=== Globus Connect Server setup completed: $(date) ==="
debug_log "SETUP COMPLETED"
exit 0