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
log "Command: $SETUP_CMD \"$GLOBUS_DISPLAY_NAME\""
SETUP_OUTPUT=$(eval $SETUP_CMD "\"$GLOBUS_DISPLAY_NAME\"" 2>&1)
SETUP_EXIT_CODE=$?

# Save raw output to file for debugging
echo "$SETUP_OUTPUT" > /home/ubuntu/endpoint-setup-output.txt

# Check setup result
if [ $SETUP_EXIT_CODE -ne 0 ]; then
  log "Endpoint setup failed with exit code $SETUP_EXIT_CODE"
  log "Setup Output: $SETUP_OUTPUT"
  exit 1
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
  
  # Now run the node setup command with the public IP
  log "Now setting up the Globus Connect Server node..."
  
  # Get the instance's public IP address - try multiple methods
  # First try the EC2 metadata service
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  
  if [ -z "$PUBLIC_IP" ]; then
    # Fallback method - try to get it from public interface
    PUBLIC_IP=$(curl -s https://checkip.amazonaws.com || curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
  fi
  
  if [ -z "$PUBLIC_IP" ]; then
    # Final fallback - try to determine from network interfaces
    PUBLIC_IP=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^10\." | grep -v "^172\." | grep -v "^192\.168" | head -1)
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
      
      # Check status of key services
      log "Checking status of Globus services..."
      systemctl status globus-gridftp-server --no-pager | grep -E "Active:|Main PID:" > /home/ubuntu/gridftp-status.txt
      systemctl status apache2 --no-pager | grep -E "Active:|Main PID:" > /home/ubuntu/apache-status.txt
      
      # Setup is successful, now check if POSIX gateway is requested
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
            
            # Create a collection for this gateway if requested
            if [ "$CREATE_POSIX_COLLECTION" = "true" ]; then
              log "Creating collection for POSIX gateway..."
              
              # Default collection name if not specified
              COLLECTION_NAME="${POSIX_COLLECTION_NAME:-$POSIX_GATEWAY_NAME Collection}"
              
              # Create the collection
              COLLECTION_CMD="globus-connect-server collection create --storage-gateway \"$GATEWAY_ID\" --display-name \"$COLLECTION_NAME\""
              log "Running command: $COLLECTION_CMD"
              
              # Execute the command
              COLLECTION_OUTPUT=$(eval $COLLECTION_CMD 2>&1)
              COLLECTION_EXIT_CODE=$?
              
              # Save output for reference
              echo "$COLLECTION_OUTPUT" > /home/ubuntu/posix-collection-output.txt
              
              if [ $COLLECTION_EXIT_CODE -eq 0 ]; then
                log "POSIX collection created successfully"
                
                # Extract collection ID
                COLLECTION_ID=$(echo "$COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
                if [ -n "$COLLECTION_ID" ]; then
                  log "Extracted collection ID: $COLLECTION_ID"
                  echo "$COLLECTION_ID" > /home/ubuntu/posix-collection-id.txt
                  
                  # Create URL for collection access
                  echo "https://app.globus.org/file-manager?destination_id=$COLLECTION_ID" > /home/ubuntu/posix-collection-url.txt
                fi
              else
                log "Failed to create POSIX collection"
                echo "Failed to create POSIX collection with exit code $COLLECTION_EXIT_CODE" > /home/ubuntu/POSIX_COLLECTION_FAILED.txt
                echo "Please check the output in posix-collection-output.txt" >> /home/ubuntu/POSIX_COLLECTION_FAILED.txt
              fi
            fi
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

ENDPOINT_UUID=""
if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
  ENDPOINT_UUID=$(cat /home/ubuntu/endpoint-uuid.txt)
fi

if [ -z "$ENDPOINT_UUID" ]; then
  echo "No endpoint UUID found. Run show-endpoint.sh first to get the UUID."
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

# Check if POSIX gateway was created
POSIX_GATEWAY_STATUS="Not configured"
POSIX_GATEWAY_ID=""
POSIX_COLLECTION_URL=""

if [ -f /home/ubuntu/posix-gateway-id.txt ]; then
  POSIX_GATEWAY_ID=$(cat /home/ubuntu/posix-gateway-id.txt)
  POSIX_GATEWAY_STATUS="Created - ID: $POSIX_GATEWAY_ID"
  
  # Check if collection was created
  if [ -f /home/ubuntu/posix-collection-id.txt ]; then
    POSIX_COLLECTION_ID=$(cat /home/ubuntu/posix-collection-id.txt)
    POSIX_COLLECTION_URL=$(cat /home/ubuntu/posix-collection-url.txt 2>/dev/null || echo "")
    POSIX_GATEWAY_STATUS="$POSIX_GATEWAY_STATUS, Collection ID: $POSIX_COLLECTION_ID"
  fi
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
- Node Command: sudo globus-connect-server node setup --ip-address $PUBLIC_IP

Storage Gateways:
- POSIX Gateway: $POSIX_GATEWAY_STATUS

Access Information:
- Endpoint URL: https://app.globus.org/file-manager?origin_id=${ENDPOINT_UUID:-MISSING_UUID}
$([ -n "$POSIX_COLLECTION_URL" ] && echo "- POSIX Collection URL: $POSIX_COLLECTION_URL" || echo "")

Helper Scripts:
- /home/ubuntu/show-endpoint.sh: Show endpoint details
- /home/ubuntu/globus-cli-examples.sh: Examples of common Globus CLI commands

Service Status:
- Apache2: $(systemctl is-active apache2 2>/dev/null || echo "Unknown")
- GridFTP: $(systemctl is-active globus-gridftp-server 2>/dev/null || echo "Unknown")
EOF

# Set permissions
chown -R ubuntu:ubuntu /home/ubuntu/

log "=== Globus Connect Server setup completed: $(date) ==="
exit 0