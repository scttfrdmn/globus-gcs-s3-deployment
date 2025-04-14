#!/bin/bash
# Globus Connect Server deployment script
# Following Globus documentation: https://docs.globus.org/globus-connect-server/v5.4/automated-deployment/

# Enable error handling
set -e
set -o pipefail

# Create and use a log file
LOG_FILE="/var/log/globus-setup.log"
touch "$LOG_FILE" 2>/dev/null || {
  # If we can't write to /var/log, use a local log file
  LOG_FILE="/tmp/globus-setup.log"
  touch "$LOG_FILE"
}

# Logging function
log() {
  echo "$@" | tee -a "$LOG_FILE" 2>/dev/null
}

# Special debugging function for command execution
run_command() {
  local cmd="$1"
  local desc="$2"
  
  log "Running command: $cmd"
  log "Description: $desc"
  
  # Create a script with the command
  TMP_SCRIPT=$(mktemp)
  echo "#!/bin/bash" > "$TMP_SCRIPT"
  echo "set -e" >> "$TMP_SCRIPT"
  echo "# Generated command script for $desc" >> "$TMP_SCRIPT"
  echo "$cmd" >> "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"
  
  # Execute it with set +e to capture return code
  set +e
  "$TMP_SCRIPT" 2>&1
  local rc=$?
  set -e
  
  # Clean up
  rm -f "$TMP_SCRIPT"
  
  # Return the exit code
  return $rc
}

# Error handling function
handle_error() {
  local error_message="$1"
  log "ERROR: $error_message"
  exit 1
}

log "=== Starting Globus Connect Server setup: $(date) ==="

# Enable debug mode for more verbose output if needed
DEBUG_MODE="${DEBUG_MODE:-false}"

# Function to print debug information only when in debug mode
debug() {
  if [ "$DEBUG_MODE" = "true" ]; then
    log "[DEBUG] $@"
  fi
}

# Read environment variables passed from CloudFormation
GLOBUS_CLIENT_ID="${GLOBUS_CLIENT_ID:-}"
GLOBUS_CLIENT_SECRET="${GLOBUS_CLIENT_SECRET:-}"
GLOBUS_DISPLAY_NAME="${GLOBUS_DISPLAY_NAME:-}"
GLOBUS_ORGANIZATION="${GLOBUS_ORGANIZATION:-}"
GLOBUS_OWNER="${GLOBUS_OWNER:-}"
GLOBUS_CONTACT_EMAIL="${GLOBUS_CONTACT_EMAIL:-}"
GLOBUS_PROJECT_ID="${GLOBUS_PROJECT_ID:-}"
GLOBUS_SUBSCRIPTION_ID="${GLOBUS_SUBSCRIPTION_ID:-}"
RESET_ENDPOINT_OWNER="${RESET_ENDPOINT_OWNER:-true}"
ENDPOINT_RESET_OWNER_TARGET="${ENDPOINT_RESET_OWNER_TARGET:-GlobusOwner}"
ENABLE_S3_CONNECTOR="${ENABLE_S3_CONNECTOR:-false}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-}"

# Set debug mode if requested
if [ "$DEBUG_MODE" = "true" ]; then
  log "Debug mode enabled - will show detailed debugging information"
  set -x  # Enable command echoing in debug mode
fi

# Save parameters to files for reference
mkdir -p /home/ubuntu
echo "$GLOBUS_CLIENT_ID" > /home/ubuntu/globus-client-id.txt
echo "$GLOBUS_CLIENT_SECRET" > /home/ubuntu/globus-client-secret.txt
echo "$GLOBUS_DISPLAY_NAME" > /home/ubuntu/globus-display-name.txt
echo "$GLOBUS_ORGANIZATION" > /home/ubuntu/globus-organization.txt
echo "$GLOBUS_OWNER" > /home/ubuntu/globus-owner.txt
echo "$GLOBUS_CONTACT_EMAIL" > /home/ubuntu/globus-contact-email.txt
chmod 600 /home/ubuntu/globus-client-*.txt

# Validate critical parameters
if [ -z "$GLOBUS_CLIENT_ID" ] || [ -z "$GLOBUS_CLIENT_SECRET" ]; then
  handle_error "Missing client credentials. GLOBUS_CLIENT_ID and GLOBUS_CLIENT_SECRET are required."
fi

if [ -z "$GLOBUS_DISPLAY_NAME" ]; then
  handle_error "Missing display name. GLOBUS_DISPLAY_NAME is required."
fi

if [ -z "$GLOBUS_ORGANIZATION" ]; then
  handle_error "Missing organization. GLOBUS_ORGANIZATION is required."
fi

if [ -z "$GLOBUS_OWNER" ]; then
  handle_error "Missing endpoint owner. GLOBUS_OWNER is required."
fi

if [ -z "$GLOBUS_CONTACT_EMAIL" ]; then
  handle_error "Missing contact email. GLOBUS_CONTACT_EMAIL is required."
fi

if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ -z "$S3_BUCKET_NAME" ]; then
  handle_error "S3 connector enabled but S3_BUCKET_NAME not provided."
fi

if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ -z "$GLOBUS_SUBSCRIPTION_ID" ]; then
  handle_error "S3 connector enabled but GLOBUS_SUBSCRIPTION_ID not provided."
fi

# Check if we're running as root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    log "Not running as root, using sudo for installation commands"
    SUDO="sudo"
  else
    handle_error "This script must be run as root or with sudo"
  fi
fi

# Install Globus Connect Server
log "Installing dependencies..."
$SUDO apt-get update
$SUDO apt-get install -y curl wget apt-transport-https ca-certificates

# Add Globus repository
log "Adding Globus repository..."
cd /tmp
curl -LOs https://downloads.globus.org/globus-connect-server/stable/installers/repo/deb/globus-repo_latest_all.deb
if [ ! -f /tmp/globus-repo_latest_all.deb ]; then
  handle_error "Failed to download Globus repository package."
fi

$SUDO dpkg -i /tmp/globus-repo_latest_all.deb
$SUDO apt-get update

# Install Globus Connect Server package (correct Ubuntu package)
log "Installing Globus Connect Server 54 package..."
$SUDO apt-get install -y globus-connect-server54

# Verify installation with extra diagnostics
log "Current PATH: $PATH"

# Collect system state for debugging
log "Creating diagnostic outputs..."
command -v globus-connect-server > /home/ubuntu/globus-command-path.txt 2>&1 || echo "Not found" > /home/ubuntu/globus-command-path.txt
find /usr -name "globus-connect-server*" > /home/ubuntu/globus-find-results.txt 2>&1 || true
ls -la /usr/bin/globus* > /home/ubuntu/globus-binaries.txt 2>&1 || true
dpkg -l | grep globus > /home/ubuntu/globus-packages.txt 2>&1 || true

if ! command -v globus-connect-server &> /dev/null; then
  log "Command not found in PATH. Checking common locations..."
  
  # Search more aggressively for the command
  for location in /usr/bin /usr/local/bin /usr/share/globus-connect-server/bin /opt/globus-connect-server/bin
  do
    if [ -x "$location/globus-connect-server" ]; then
      log "Found in $location/globus-connect-server"
      export PATH="$location:$PATH"
      break
    fi
  done
  
  # If we found it, great! If not, keep looking
  if ! command -v globus-connect-server &> /dev/null; then
    # Last-ditch effort: find it anywhere in /usr
    GLOB_PATH=$(find /usr -name "globus-connect-server" -type f -executable 2>/dev/null | head -1)
    
    if [ -n "$GLOB_PATH" ]; then
      log "Found globus-connect-server at $GLOB_PATH"
      GLOB_DIR=$(dirname "$GLOB_PATH")
      export PATH="$GLOB_DIR:$PATH"
    else
      log "Detailed diagnostic information:"
      log "$(cat /home/ubuntu/globus-find-results.txt)"
      log "$(cat /home/ubuntu/globus-packages.txt)"
      handle_error "Globus Connect Server installation failed. Command not found in any common location."
    fi
  fi
fi

# Make sure the command works before proceeding
if command -v globus-connect-server &> /dev/null; then
  GLOB_CMD=$(which globus-connect-server)
  log "Using Globus Connect Server binary: $GLOB_CMD"
  ls -la $GLOB_CMD >> /home/ubuntu/globus-command-details.txt
else
  handle_error "Globus Connect Server command still not found after path adjustments."
fi

# Check Globus Connect Server version
log "Checking Globus Connect Server version..."
GCS_VERSION_RAW=$(globus-connect-server --version 2>&1)
log "Raw version output: $GCS_VERSION_RAW"

# Extract version - attempt to get package version first (format: "package X.Y.Z")
GCS_VERSION_PACKAGE=$(echo "$GCS_VERSION_RAW" | grep -o "package [0-9]\+\.[0-9]\+\.[0-9]\+" | awk '{print $2}' || echo "")

if [ -n "$GCS_VERSION_PACKAGE" ]; then
  GCS_VERSION="$GCS_VERSION_PACKAGE"
  log "Detected version (package format): $GCS_VERSION"
else
  # Fallback to any version number pattern
  GCS_VERSION=$(echo "$GCS_VERSION_RAW" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [ -z "$GCS_VERSION" ]; then
    log "WARNING: Could not detect version. Assuming compatible version."
    GCS_VERSION="5.4.99" # Assume compatible version
  else
    log "Detected version (fallback method): $GCS_VERSION"
  fi
fi

# Check version compatibility - require 5.4.61+
REQUIRED_VERSION="5.4.61"
log "Checking if version $GCS_VERSION >= $REQUIRED_VERSION"

# Extract components for comparison
MAJOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f1)
MINOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f2)
PATCH_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f3)

MAJOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f1)
MINOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f2)
PATCH_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f3)

# Perform semver comparison
if [ "$MAJOR_CURRENT" -gt "$MAJOR_REQUIRED" ] || 
   ([ "$MAJOR_CURRENT" -eq "$MAJOR_REQUIRED" ] && [ "$MINOR_CURRENT" -gt "$MINOR_REQUIRED" ]) || 
   ([ "$MAJOR_CURRENT" -eq "$MAJOR_REQUIRED" ] && [ "$MINOR_CURRENT" -eq "$MINOR_REQUIRED" ] && [ "$PATCH_CURRENT" -ge "$PATCH_REQUIRED" ]); then
  log "✅ Version check passed: $GCS_VERSION meets or exceeds required version $REQUIRED_VERSION"
else
  handle_error "Version check failed: $GCS_VERSION is older than required version $REQUIRED_VERSION"
fi

# Set environment variables for Globus CLI authentication
export GCS_CLI_CLIENT_ID="$GLOBUS_CLIENT_ID"
export GCS_CLI_CLIENT_SECRET="$GLOBUS_CLIENT_SECRET"

# Check for existing endpoint with same name to avoid duplication
log "Checking for existing endpoint with name '$GLOBUS_DISPLAY_NAME'..."
EXISTING_ENDPOINT=""

# First try globus-connect-server endpoint list
EXISTING_ENDPOINT=$(globus-connect-server endpoint list 2>/dev/null | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")

if [ -z "$EXISTING_ENDPOINT" ]; then
  log "No existing endpoint found with name '$GLOBUS_DISPLAY_NAME'"
  
  # Prepare endpoint setup command
  SETUP_CMD="globus-connect-server endpoint setup"
  SETUP_CMD+=" --organization \"$GLOBUS_ORGANIZATION\""
  SETUP_CMD+=" --contact-email \"$GLOBUS_CONTACT_EMAIL\""
  SETUP_CMD+=" --owner \"$GLOBUS_OWNER\""
  SETUP_CMD+=" --dont-set-advertised-owner"  # Recommended for service identity authentication
  SETUP_CMD+=" --agree-to-letsencrypt-tos"

  # Add project ID if specified (required when service identity has access to multiple projects)
  if [ -n "$GLOBUS_PROJECT_ID" ]; then
    SETUP_CMD+=" --project-id \"$GLOBUS_PROJECT_ID\""
  fi
  
  # Run endpoint setup and capture output
  log "Setting up endpoint with display name: $GLOBUS_DISPLAY_NAME"
  log "Running command: $SETUP_CMD \"$GLOBUS_DISPLAY_NAME\""
  
  # First make an explicit check for connectivity to Globus
  log "Testing connectivity to Globus services..."
  if ! curl -s --connect-timeout 10 https://auth.globus.org > /dev/null; then
    log "WARNING: Cannot connect to Globus Auth service. Check network connectivity."
  fi
  
  # Write the exact command to a file for debugging
  echo "$SETUP_CMD \"$GLOBUS_DISPLAY_NAME\"" > /home/ubuntu/endpoint-setup-command.txt
  
  # Try a simpler direct approach first (more likely to succeed)
  log "Executing globus-connect-server directly without eval..."
  
  # Build arguments array to avoid quoting/eval issues
  DIRECT_ARGS=("endpoint" "setup" 
              "--organization" "$GLOBUS_ORGANIZATION"
              "--contact-email" "$GLOBUS_CONTACT_EMAIL"
              "--owner" "$GLOBUS_OWNER"
              "--dont-set-advertised-owner"
              "--agree-to-letsencrypt-tos")
  
  # Add project ID if specified
  if [ -n "$GLOBUS_PROJECT_ID" ]; then
    DIRECT_ARGS+=("--project-id" "$GLOBUS_PROJECT_ID")
  fi
  
  # Add display name (positional argument)
  DIRECT_ARGS+=("$GLOBUS_DISPLAY_NAME")
  
  # Save command for debugging
  echo "globus-connect-server ${DIRECT_ARGS[@]}" > /home/ubuntu/endpoint-setup-direct-command.txt
  
  # Run the command and capture output
  set +e
  DIRECT_OUTPUT=$(globus-connect-server "${DIRECT_ARGS[@]}" 2>&1)
  DIRECT_EXIT_CODE=$?
  set -e
  
  # Save output for debugging
  echo "$DIRECT_OUTPUT" > /home/ubuntu/endpoint-setup-direct.txt
  
  if [ $DIRECT_EXIT_CODE -eq 0 ]; then
    log "✅ Direct command execution succeeded!"
    SETUP_OUTPUT="$DIRECT_OUTPUT"
    SETUP_EXIT_CODE=0
  else
    log "Direct command failed with exit code $DIRECT_EXIT_CODE, trying alternative methods..."
    
    # Try the original eval approach as fallback
    set +e
    eval $SETUP_CMD "\"$GLOBUS_DISPLAY_NAME\"" > /home/ubuntu/endpoint-setup-output.raw 2>&1
    SETUP_EXIT_CODE=$?
    set -e
    
    # If both failed, try one more approach with explicit globus-connect-server path
    if [ $SETUP_EXIT_CODE -ne 0 ]; then
      log "Both methods failed, trying with full path to globus-connect-server..."
      GLOB_CMD=$(which globus-connect-server)
      
      if [ -n "$GLOB_CMD" ]; then
        set +e
        "$GLOB_CMD" "${DIRECT_ARGS[@]}" > /home/ubuntu/endpoint-setup-fullpath.txt 2>&1
        FULL_PATH_EXIT_CODE=$?
        set -e
        
        if [ $FULL_PATH_EXIT_CODE -eq 0 ]; then
          log "✅ Full path command execution succeeded!"
          SETUP_OUTPUT=$(cat /home/ubuntu/endpoint-setup-fullpath.txt)
          SETUP_EXIT_CODE=0
        else
          # If all methods failed, use the direct output for error reporting
          SETUP_OUTPUT="$DIRECT_OUTPUT"
        fi
      fi
    else
      # If eval method worked, use its output
      SETUP_OUTPUT=$(cat /home/ubuntu/endpoint-setup-output.raw)
    fi
  fi
  
  # Save the final output regardless of which method was used
  echo "$SETUP_OUTPUT" > /home/ubuntu/endpoint-setup-output.txt
  
  # Display the output
  log "Command completed with exit code: $SETUP_EXIT_CODE"
  
  # More detailed error handling
  if [ $SETUP_EXIT_CODE -ne 0 ]; then
    log "===== ENDPOINT SETUP ERROR DETAILS ====="
    log "Exit code: $SETUP_EXIT_CODE"
    
    # Look for common error patterns
    if echo "$SETUP_OUTPUT" | grep -q "Unauthorized"; then
      log "ERROR: Authentication failed. Check client credentials."
      echo "AUTHENTICATION_ERROR" > /home/ubuntu/SETUP_ERROR_TYPE.txt
    elif echo "$SETUP_OUTPUT" | grep -q "timeout"; then
      log "ERROR: Connection timed out. Check network connectivity."
      echo "TIMEOUT_ERROR" > /home/ubuntu/SETUP_ERROR_TYPE.txt
    elif echo "$SETUP_OUTPUT" | grep -q "NoSuchDisplayName"; then
      log "ERROR: Project ID may be incorrect or client doesn't have access."
      echo "PROJECT_ACCESS_ERROR" > /home/ubuntu/SETUP_ERROR_TYPE.txt
    elif echo "$SETUP_OUTPUT" | grep -q "permission"; then
      log "ERROR: Permission denied. Check client permissions."
      echo "PERMISSION_ERROR" > /home/ubuntu/SETUP_ERROR_TYPE.txt
    else
      log "ERROR: Unknown error during endpoint setup."
      echo "UNKNOWN_ERROR" > /home/ubuntu/SETUP_ERROR_TYPE.txt
    fi
    
    # Save environment state for debugging
    env | grep -E 'GLOBUS|GCS_CLI' > /home/ubuntu/globus-environment.txt
    
    handle_error "Endpoint setup failed with exit code $SETUP_EXIT_CODE. See /home/ubuntu/endpoint-setup-output.txt for details."
  fi
  
  # Extract endpoint UUID from output
  log "Extracting endpoint UUID from command output..."
  ENDPOINT_UUID=$(echo "$SETUP_OUTPUT" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
  
  if [ -n "$ENDPOINT_UUID" ]; then
    log "Successfully extracted endpoint UUID: $ENDPOINT_UUID"
    # Ensure directory exists with proper permissions
    mkdir -p /home/ubuntu
    # Write the UUID to files with explicit permissions
    echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
    echo "ENDPOINT UUID: $ENDPOINT_UUID" > /home/ubuntu/ENDPOINT_UUID.txt
    chown ubuntu:ubuntu /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
    chmod 644 /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
    export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
    # Log verification that the file was created
    ls -la /home/ubuntu/endpoint-uuid.txt | tee -a "$LOG_FILE"
    
    # Verify the endpoint was actually created by trying to get its details
    log "Verifying endpoint creation..."
    set +e
    VERIFY_OUTPUT=$(globus-connect-server endpoint show 2>&1)
    VERIFY_EXIT_CODE=$?
    set -e
    
    if [ $VERIFY_EXIT_CODE -eq 0 ] && echo "$VERIFY_OUTPUT" | grep -q "$ENDPOINT_UUID"; then
      log "✅ Endpoint verification successful!"
      echo "$VERIFY_OUTPUT" > /home/ubuntu/endpoint-verify-success.txt
    else
      log "⚠️ Endpoint may have been created but verification failed."
      log "Verify output: $VERIFY_OUTPUT"
      echo "$VERIFY_OUTPUT" > /home/ubuntu/endpoint-verify-failed.txt
      
      # Try to find additional information about what might be wrong
      log "Checking endpoint list for additional information..."
      globus-connect-server endpoint list > /home/ubuntu/endpoint-list.txt 2>&1 || true
      
      # Try to set the GCS_CLI_ENDPOINT_ID environment variable again to be sure
      export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
      log "Re-exported GCS_CLI_ENDPOINT_ID=$ENDPOINT_UUID"
    fi
  else
    log "WARNING: Could not extract endpoint UUID from output"
    echo "WARNING: Could not extract endpoint UUID from output" > /home/ubuntu/MISSING_UUID.txt
    echo "Check endpoint-setup-output.txt for the full output and look for the UUID manually." >> /home/ubuntu/MISSING_UUID.txt
    
    # Save the full command output for detailed inspection
    echo "======== FULL COMMAND OUTPUT ========" >> /home/ubuntu/endpoint-setup-detailed.txt
    echo "$SETUP_OUTPUT" >> /home/ubuntu/endpoint-setup-detailed.txt
    
    # Try alternative methods to find the endpoint
    log "Trying alternative methods to find the endpoint..."
    
    # Try to extract the UUID using additional patterns that might appear in the output
    log "Attempting alternative extraction patterns..."
    ALT_PATTERNS=(
      "endpoint id: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
      "endpoint ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
      "id: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
      "id ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
      "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
    )
    
    for pattern in "${ALT_PATTERNS[@]}"; do
      log "Trying pattern: $pattern"
      PATTERN_UUID=$(echo "$SETUP_OUTPUT" | grep -oE "$pattern" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
      if [ -n "$PATTERN_UUID" ]; then
        log "Found UUID with alternative pattern: $PATTERN_UUID"
        ENDPOINT_UUID="$PATTERN_UUID"
        echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
        echo "ENDPOINT UUID: $ENDPOINT_UUID (from pattern extraction)" > /home/ubuntu/ENDPOINT_UUID.txt
        chown ubuntu:ubuntu /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
        chmod 644 /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
        export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
        ls -la /home/ubuntu/endpoint-uuid.txt | tee -a "$LOG_FILE"
        break
      fi
    done
    
    # If still not found, check endpoint list as last resort
    if [ -z "$ENDPOINT_UUID" ]; then
      log "No UUID found with pattern extraction, checking endpoint list..."
      
      # Try the endpoint list command
      set +e
      ENDPOINT_LIST=$(globus-connect-server endpoint list 2>&1)
      ENDPOINT_LIST_EXIT_CODE=$?
      set -e
      
      echo "======== ENDPOINT LIST OUTPUT ========" >> /home/ubuntu/endpoint-list-detailed.txt
      echo "$ENDPOINT_LIST" >> /home/ubuntu/endpoint-list-detailed.txt
      
      if [ $ENDPOINT_LIST_EXIT_CODE -eq 0 ]; then
        # Filter for our endpoint name
        FOUND_ENDPOINT=$(echo "$ENDPOINT_LIST" | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")
        if [ -n "$FOUND_ENDPOINT" ]; then
          log "Found endpoint in list despite missing UUID in setup output!"
          echo "$FOUND_ENDPOINT" > /home/ubuntu/found-endpoint-in-list.txt
          
          # Try to extract the UUID
          ALT_UUID=$(echo "$FOUND_ENDPOINT" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
          
          if [ -n "$ALT_UUID" ]; then
            log "Successfully extracted endpoint UUID from list: $ALT_UUID"
            ENDPOINT_UUID="$ALT_UUID"
            echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
            echo "ENDPOINT UUID: $ENDPOINT_UUID (from endpoint list)" > /home/ubuntu/ENDPOINT_UUID.txt
            chown ubuntu:ubuntu /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
            chmod 644 /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
            export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
            ls -la /home/ubuntu/endpoint-uuid.txt | tee -a "$LOG_FILE"
          else
            log "Found endpoint but couldn't extract UUID from list"
          fi
        else
          log "Did not find endpoint with name '$GLOBUS_DISPLAY_NAME' in endpoint list"
        fi
      else
        log "Endpoint list command failed with exit code $ENDPOINT_LIST_EXIT_CODE"
      fi
    fi
    
    # Still no UUID? Try a desperate approach with endpoint show
    if [ -z "$ENDPOINT_UUID" ]; then
      log "Last resort: trying endpoint show command..."
      set +e
      SHOW_OUTPUT=$(globus-connect-server endpoint show 2>&1)
      SHOW_EXIT_CODE=$?
      set -e
      
      echo "======== ENDPOINT SHOW OUTPUT ========" >> /home/ubuntu/endpoint-show-desperate.txt
      echo "$SHOW_OUTPUT" >> /home/ubuntu/endpoint-show-desperate.txt
      
      if [ $SHOW_EXIT_CODE -eq 0 ]; then
        LAST_UUID=$(echo "$SHOW_OUTPUT" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
        if [ -n "$LAST_UUID" ]; then
          log "Found UUID via show command as last resort: $LAST_UUID"
          ENDPOINT_UUID="$LAST_UUID"
          echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
          echo "ENDPOINT UUID: $ENDPOINT_UUID (from show command)" > /home/ubuntu/ENDPOINT_UUID.txt
          chown ubuntu:ubuntu /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
          chmod 644 /home/ubuntu/endpoint-uuid.txt /home/ubuntu/ENDPOINT_UUID.txt
          export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
          ls -la /home/ubuntu/endpoint-uuid.txt | tee -a "$LOG_FILE"
        fi
      fi
    fi
  fi
else
  # Extract UUID from existing endpoint
  log "Found existing endpoint with name '$GLOBUS_DISPLAY_NAME'"
  log "Existing endpoint details: $EXISTING_ENDPOINT"
  
  ENDPOINT_UUID=$(echo "$EXISTING_ENDPOINT" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
  
  if [ -n "$ENDPOINT_UUID" ]; then
    log "Extracted UUID from existing endpoint: $ENDPOINT_UUID"
    echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
    echo "ENDPOINT UUID: $ENDPOINT_UUID" > /home/ubuntu/ENDPOINT_UUID.txt
    export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
  else
    log "WARNING: Could not extract UUID from existing endpoint entry: $EXISTING_ENDPOINT"
  fi
fi

# Reset advertised owner if requested and we have a UUID
if [ "$RESET_ENDPOINT_OWNER" = "true" ] && [ -n "$ENDPOINT_UUID" ]; then
  log "Resetting endpoint advertised owner..."
  
  # Determine which identity to use as the advertised owner
  OWNER_IDENTITY=""
  case "$ENDPOINT_RESET_OWNER_TARGET" in
    "GlobusOwner")
      OWNER_IDENTITY="$GLOBUS_OWNER"
      ;;
    "GlobusContactEmail")
      OWNER_IDENTITY="$GLOBUS_CONTACT_EMAIL"
      ;;
    *)
      OWNER_IDENTITY="$GLOBUS_OWNER"
      ;;
  esac
  
  if [ -n "$OWNER_IDENTITY" ]; then
    log "Setting advertised owner to: $OWNER_IDENTITY"
    globus-connect-server endpoint set-owner-string "$OWNER_IDENTITY" | tee -a $LOG_FILE
    
    # Verify the change
    log "Updated endpoint details:"
    globus-connect-server endpoint show | tee -a $LOG_FILE | tee /home/ubuntu/endpoint-details.txt
  else
    log "WARNING: No valid identity found for setting advertised owner"
  fi
fi

# Set subscription ID if provided (required for S3 connector)
if [ -n "$GLOBUS_SUBSCRIPTION_ID" ] && [ -n "$ENDPOINT_UUID" ]; then
  log "Setting endpoint subscription ID: $GLOBUS_SUBSCRIPTION_ID"
  
  if [ "$GLOBUS_SUBSCRIPTION_ID" = "DEFAULT" ]; then
    log "Using DEFAULT subscription"
    globus-connect-server endpoint set-subscription-id DEFAULT | tee -a $LOG_FILE
  else
    log "Using specific subscription ID"
    globus-connect-server endpoint set-subscription-id "$GLOBUS_SUBSCRIPTION_ID" | tee -a $LOG_FILE
  fi
  
  SUBSCRIPTION_RESULT=$?
  if [ $SUBSCRIPTION_RESULT -ne 0 ]; then
    log "WARNING: Failed to set subscription ID. S3 connector will not work."
    echo "===================== SUBSCRIPTION SETUP WARNING =====================" > /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "Failed to set subscription ID for this endpoint." >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "S3 connector features will not work until this is resolved." >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "Common causes:" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "1. The endpoint owner (${GLOBUS_OWNER}) doesn't have subscription manager role" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "2. The project was not created by someone with subscription manager rights" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "To fix:" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "Have a subscription manager run: globus-connect-server endpoint set-subscription-id DEFAULT" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "OR set it through the Globus web interface under endpoint settings" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
    echo "====================================================================" >> /home/ubuntu/SUBSCRIPTION_WARNING.txt
  fi
fi

# Set up S3 connector if enabled and we have a subscription and endpoint UUID
if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ -n "$GLOBUS_SUBSCRIPTION_ID" ] && [ -n "$ENDPOINT_UUID" ]; then
  log "Setting up S3 connector for bucket: $S3_BUCKET_NAME"
  
  # Verify S3 bucket exists and is accessible
  log "Verifying S3 bucket accessibility: $S3_BUCKET_NAME"
  if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
    log "S3 bucket verified: $S3_BUCKET_NAME"
    
    # Create storage gateway for S3
    log "Creating S3 storage gateway..."
    GATEWAY_OUTPUT=$(globus-connect-server storage-gateway create s3 \
      --display-name "S3 Storage" \
      --domain s3.amazonaws.com \
      --bucket "$S3_BUCKET_NAME" 2>&1)
    
    log "$GATEWAY_OUTPUT"
    
    # Extract gateway ID
    GATEWAY_ID=$(echo "$GATEWAY_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
    
    if [ -n "$GATEWAY_ID" ]; then
      log "Successfully created S3 storage gateway with ID: $GATEWAY_ID"
      echo "$GATEWAY_ID" > /home/ubuntu/s3-gateway-id.txt
      
      # Create a collection with this gateway
      log "Creating collection for S3 bucket..."
      COLLECTION_OUTPUT=$(globus-connect-server collection create \
        --storage-gateway "$GATEWAY_ID" \
        --display-name "$GLOBUS_DISPLAY_NAME S3 Collection" 2>&1)
      
      log "$COLLECTION_OUTPUT"
      
      # Extract collection ID
      COLLECTION_ID=$(echo "$COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)
      
      if [ -n "$COLLECTION_ID" ]; then
        log "Successfully created collection with ID: $COLLECTION_ID"
        echo "$COLLECTION_ID" > /home/ubuntu/s3-collection-id.txt
        
        # Save URL for collection access
        COLLECTION_URL="https://app.globus.org/file-manager?destination_id=$COLLECTION_ID"
        log "Collection URL: $COLLECTION_URL"
        echo "$COLLECTION_URL" > /home/ubuntu/s3-collection-url.txt
      else
        log "WARNING: Could not extract collection ID from output"
      fi
    else
      log "WARNING: Could not extract gateway ID from output"
    fi
  else
    log "ERROR: S3 bucket '$S3_BUCKET_NAME' not accessible. Check IAM permissions and bucket name."
  fi
fi

# Create a simple helper script for creating S3 collections
cat > /home/ubuntu/create-s3-collection.sh << 'EOF'
#!/bin/bash
# Helper script to create a Globus S3 collection

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <s3-bucket-name>"
  echo "Example: $0 my-globus-bucket"
  exit 1
fi

S3_BUCKET_NAME="$1"

# Try multiple methods to retrieve the endpoint UUID
find_endpoint_uuid() {
  # Try the endpoint-uuid.txt file first
  if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
    local uuid=$(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      echo "$uuid"
      return 0
    fi
  fi
  
  # Try ENDPOINT_UUID.txt next
  if [ -f /home/ubuntu/ENDPOINT_UUID.txt ]; then
    local uuid=$(cat /home/ubuntu/ENDPOINT_UUID.txt 2>/dev/null | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      echo "$uuid"
      return 0
    fi
  fi
  
  # Try to get UUID from endpoint show command
  if command -v globus-connect-server >/dev/null 2>&1; then
    if [ -f /home/ubuntu/globus-client-id.txt ] && [ -f /home/ubuntu/globus-client-secret.txt ]; then
      export GCS_CLI_CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
      export GCS_CLI_CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
      
      local show_output=$(globus-connect-server endpoint show 2>/dev/null)
      local uuid=$(echo "$show_output" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
      if [ -n "$uuid" ]; then
        # Save it for future use
        echo "$uuid" > /home/ubuntu/endpoint-uuid.txt
        echo "$uuid"
        return 0
      fi
    fi
  fi
  
  # Last resort: search in any files that might contain the UUID
  local search_result=$(grep -r -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" /home/ubuntu/ 2>/dev/null | head -1)
  if [ -n "$search_result" ]; then
    local uuid=$(echo "$search_result" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      # Save it for future use
      echo "$uuid" > /home/ubuntu/endpoint-uuid.txt
      echo "$uuid"
      return 0
    fi
  fi
  
  return 1
}

ENDPOINT_UUID=$(find_endpoint_uuid)

# Check if endpoint UUID is available
if [ -z "$ENDPOINT_UUID" ]; then
  echo "ERROR: Endpoint UUID not found. Please ensure the endpoint was created successfully."
  echo "Troubleshooting steps:"
  echo "1. Check if the endpoint was created by running: globus-connect-server endpoint list"
  echo "2. Look in log files: /home/ubuntu/globus-setup.log and /var/log/globus-setup.log"
  echo "3. If you find the UUID manually, save it to /home/ubuntu/endpoint-uuid.txt"
  exit 1
fi

echo "Using endpoint UUID: $ENDPOINT_UUID"

# Set up environment
if [ -f /home/ubuntu/globus-client-id.txt ] && [ -f /home/ubuntu/globus-client-secret.txt ]; then
  export GCS_CLI_CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
  export GCS_CLI_CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
  export GCS_CLI_ENDPOINT_ID="$ENDPOINT_UUID"
else
  echo "ERROR: Globus credentials not found."
  exit 1
fi

# Verify S3 bucket exists
echo "Verifying S3 bucket accessibility: $S3_BUCKET_NAME"
if ! aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
  echo "ERROR: Cannot access S3 bucket $S3_BUCKET_NAME. Check permissions and bucket name."
  exit 1
fi

# Create storage gateway
echo "Creating S3 storage gateway..."
GATEWAY_OUTPUT=$(globus-connect-server storage-gateway create s3 \
  --display-name "S3 Storage ($S3_BUCKET_NAME)" \
  --domain s3.amazonaws.com \
  --bucket "$S3_BUCKET_NAME" 2>&1)

echo "$GATEWAY_OUTPUT"

# Extract gateway ID
GATEWAY_ID=$(echo "$GATEWAY_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)

if [ -z "$GATEWAY_ID" ]; then
  echo "ERROR: Failed to create storage gateway or extract gateway ID."
  exit 1
fi

# Create collection
echo "Creating collection..."
COLLECTION_OUTPUT=$(globus-connect-server collection create \
  --storage-gateway "$GATEWAY_ID" \
  --display-name "S3 Collection ($S3_BUCKET_NAME)" 2>&1)

echo "$COLLECTION_OUTPUT"

# Extract collection ID
COLLECTION_ID=$(echo "$COLLECTION_OUTPUT" | grep -i "id:" | awk '{print $2}' | head -1)

if [ -n "$COLLECTION_ID" ]; then
  echo "SUCCESS: Collection created with ID: $COLLECTION_ID"
  COLLECTION_URL="https://app.globus.org/file-manager?destination_id=$COLLECTION_ID"
  echo "Collection URL: $COLLECTION_URL"
else
  echo "ERROR: Failed to create collection or extract collection ID."
  exit 1
fi
EOF

chmod +x /home/ubuntu/create-s3-collection.sh
chown -R ubuntu:ubuntu /home/ubuntu/

# Final verification step: ensure endpoint UUID was found and written
log "Performing final verification of endpoint UUID..."

# Function to extract the endpoint UUID from various sources
find_endpoint_uuid() {
  # Try the endpoint-uuid.txt file first
  if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
    local uuid=$(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      echo "$uuid"
      return 0
    fi
  fi
  
  # Try ENDPOINT_UUID.txt next
  if [ -f /home/ubuntu/ENDPOINT_UUID.txt ]; then
    local uuid=$(cat /home/ubuntu/ENDPOINT_UUID.txt 2>/dev/null | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      echo "$uuid"
      return 0
    fi
  fi
  
  # Try to get UUID from endpoint show command
  if command -v globus-connect-server >/dev/null 2>&1; then
    local show_output=$(globus-connect-server endpoint show 2>/dev/null)
    local uuid=$(echo "$show_output" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      # Save it for future use
      echo "$uuid" > /home/ubuntu/endpoint-uuid.txt
      echo "$uuid"
      return 0
    fi
  fi
  
  # Last resort: search in log files that might contain the UUID
  local search_result=$(grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" /home/ubuntu/*.txt /var/log/globus-setup.log 2>/dev/null | head -1)
  if [ -n "$search_result" ]; then
    local uuid=$(echo "$search_result" | grep -o -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)
    if [ -n "$uuid" ]; then
      # Save it for future use
      echo "$uuid" > /home/ubuntu/endpoint-uuid.txt
      echo "$uuid"
      return 0
    fi
  fi
  
  return 1
}

# If we don't have an endpoint UUID yet, try to find it
if [ -z "$ENDPOINT_UUID" ]; then
  log "Endpoint UUID not found in script variables, trying to find it..."
  FINAL_UUID=$(find_endpoint_uuid)
  if [ -n "$FINAL_UUID" ]; then
    ENDPOINT_UUID="$FINAL_UUID"
    log "Successfully recovered endpoint UUID: $ENDPOINT_UUID"
    # Make sure it's written to the files
    echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
    echo "ENDPOINT UUID: $ENDPOINT_UUID (recovered during final verification)" > /home/ubuntu/ENDPOINT_UUID.txt
  else
    log "WARNING: Could not find endpoint UUID in final verification"
  fi
fi

# Create deployment summary
log "Creating deployment summary..."
cat > /home/ubuntu/deployment-summary.txt << EOF
=== Globus Connect Server Deployment Summary ===
Deployment completed: $(date)

Endpoint Details:
- Display Name: $GLOBUS_DISPLAY_NAME
- Owner: $GLOBUS_OWNER
- Organization: $GLOBUS_ORGANIZATION
- Contact Email: $GLOBUS_CONTACT_EMAIL
- UUID: ${ENDPOINT_UUID:-Not available}

Subscription Status:
- Subscription ID: ${GLOBUS_SUBSCRIPTION_ID:-None provided}
- S3 Connector Enabled: $ENABLE_S3_CONNECTOR
- S3 Bucket: ${S3_BUCKET_NAME:-None provided}

Access Information:
- Web URL: https://app.globus.org/file-manager?origin_id=${ENDPOINT_UUID:-MISSING_UUID}
- S3 Collection URL: $(cat /home/ubuntu/s3-collection-url.txt 2>/dev/null || echo "Not created")

Helper Scripts:
- /home/ubuntu/create-s3-collection.sh: Helper for creating S3 collections

UUID Status:
- UUID Found: ${ENDPOINT_UUID:+Yes}${ENDPOINT_UUID:-No}
- UUID File: $([ -f /home/ubuntu/endpoint-uuid.txt ] && echo "Exists" || echo "Missing")
- UUID Content: $(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null || echo "Empty or missing")
EOF

# Create a special file just for UUID
if [ -n "$ENDPOINT_UUID" ]; then
  echo "$ENDPOINT_UUID" > /home/ubuntu/ENDPOINT_UUID_FINAL.txt
  chmod 644 /home/ubuntu/ENDPOINT_UUID_FINAL.txt
fi

# Set permissions for logs and files
chown -R ubuntu:ubuntu /home/ubuntu/

log "=== Globus Connect Server setup completed: $(date) ==="
exit 0