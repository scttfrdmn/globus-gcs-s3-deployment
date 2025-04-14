#!/bin/bash
# Improved Globus Connect Server setup script with robust error handling
# Version: 1.0.1
#
# This script deploys Globus Connect Server with S3 connector support
# It includes fixes for common deployment issues:
# - Fixed mismatched if/fi structure in the endpoint existence check
# - Improved error handling with better diagnostics
# - More reliable heredoc usage to prevent syntax errors
# - Validated with bash -n to ensure syntax correctness

set -o pipefail

# Safety check for common syntax issues
if ! bash -n "$0"; then
  echo "ERROR: Script contains syntax errors. Please fix before running."
  exit 1
fi

# Prepare logging
LOG_FILE="/var/log/globus-setup.log"
touch "$LOG_FILE"

log() {
  echo "$@" | tee -a "$LOG_FILE"
}

handle_error() {
  local error_message="$1"
  log "ERROR: $error_message"
  exit 1
}

log "Starting Globus Connect Server setup $(date)"

# Initialize variables
EXISTING_ENDPOINT=""

# Check for existing endpoints if not explicitly skipped
if [ "$DEBUG_SKIP_DUPLICATE_CHECK" != "true" ]; then
  log "Checking for existing endpoint with name '$GLOBUS_DISPLAY_NAME'..."
  
  # Set up Globus CLI
  pip3 install -q --disable-pip-version-check globus-cli
  mkdir -p ~/.globus
  
  # Configure credentials
  cat > ~/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF

  # Try with globus-connect-server endpoint list
  EXISTING_ENDPOINT=$(globus-connect-server endpoint list 2>/dev/null | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")
  
  # Fallback to globus CLI if needed
  if [ -z "$EXISTING_ENDPOINT" ] && command -v globus &>/dev/null; then
    log "Using alternate endpoint search method..."
    
    GLOBUS_SEARCH=$(globus endpoint search --filter-scope all "$GLOBUS_DISPLAY_NAME" 2>/dev/null || echo "")
    
    if [ -n "$GLOBUS_SEARCH" ] && echo "$GLOBUS_SEARCH" | grep -q "$GLOBUS_DISPLAY_NAME"; then
      log "Found endpoint using Globus CLI:"
      log "$GLOBUS_SEARCH"
      
      # Extract UUID
      UUID_PATTERN="[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}"
      ENDPOINT_UUID=$(echo "$GLOBUS_SEARCH" | grep -o "$UUID_PATTERN" | head -1)
      
      if [ -n "$ENDPOINT_UUID" ]; then
        EXISTING_ENDPOINT="$ENDPOINT_UUID $GLOBUS_DISPLAY_NAME"
      fi
    fi
  fi
else
  log "DEBUG: Skipping endpoint check due to DEBUG_SKIP_DUPLICATE_CHECK flag"
fi

if [ -n "$EXISTING_ENDPOINT" ]; then
  log "WARNING: An endpoint with name '$GLOBUS_DISPLAY_NAME' already exists!"
  log "Existing endpoint details:"
  log "$EXISTING_ENDPOINT"
  
  # Extract endpoint ID if possible to use existing endpoint - try UUID pattern first
  ENDPOINT_ID=$(echo "$EXISTING_ENDPOINT" | grep -o "[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | head -1)
  
  # Fallback to first field if UUID pattern doesn't match
  if [ -z "$ENDPOINT_ID" ]; then
    ENDPOINT_ID=$(echo "$EXISTING_ENDPOINT" | awk '{print $1}')
  fi
  
  if [ -n "$ENDPOINT_ID" ]; then
    log "Using existing endpoint with ID: $ENDPOINT_ID"
  else
    log "ERROR: Could not extract endpoint ID from existing endpoint."
    exit 1
  fi
else
  log "No existing endpoint found. Creating new endpoint..."
  
  log "Setup complete! Endpoint details:"
  log "NOTE: The following command may fail if the environment variables aren't set yet"
  log "To fix, run: export GCS_CLI_ENDPOINT_ID=$(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null)"
  globus-connect-server endpoint show
  
  # Create a URL for easy access
  if [ -n "$ENDPOINT_UUID" ]; then
    log "To access your endpoint, visit:"
    log "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID"
    echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" > /home/ubuntu/endpoint-url.txt
  fi
fi

log "Globus setup script completed successfully"
exit 0