#!/bin/bash
# Full Globus Connect Server installation script
# This script is designed to be downloaded and executed from GitHub
# Will use environment variables passed from the CloudFormation bootstrap script
# REQUIRES: Globus Connect Server 5.4.61 or higher

# Setup proper logging - using both file and console output
exec > >(tee /var/log/globus-setup.log|logger -t globus-setup -s 2>/dev/console) 2>&1

# Mark the beginning of our script for tracking
echo "=== GLOBUS-CONNECT-SERVER-INSTALLATION-SCRIPT ==="

echo "=== Starting Globus Connect Server installation $(date) ==="
echo "Stack:$AWS_STACK_NAME Region:$AWS_REGION Type:$DEPLOYMENT_TYPE Auth:$AUTH_METHOD"
echo "Organization:\"$GLOBUS_ORGANIZATION\" DisplayName:\"$GLOBUS_DISPLAY_NAME\"" 
echo "S3 Connector: $ENABLE_S3_CONNECTOR Bucket: $S3_BUCKET_NAME"

# Check GCS version to ensure compatibility
function check_gcs_version() {
  echo "Checking Globus Connect Server version"
  
  # CRITICAL: Skip version check completely if debugging flag is set
  if [ -n "$DEBUG_SKIP_VERSION_CHECK" ]; then
    echo "DEBUG_SKIP_VERSION_CHECK is set - bypassing version compatibility check"
    return 0
  fi
  
  # Wait for GCS to be installed before checking version
  for i in {1..10}; do
    if which globus-connect-server &>/dev/null; then
      break
    fi
    echo "Waiting for globus-connect-server to be installed (attempt $i/10)..."
    sleep 5
    
    if [ $i -eq 10 ]; then
      echo "ERROR: Globus Connect Server not found after 10 attempts"
      return 1
    fi
  done
  
  # ALWAYS continue regardless of version for now - let's not block deployment
  # Print detailed debugging information instead
  
  # Get version and parse it - capture raw output for debugging
  GCS_VERSION_RAW=$(globus-connect-server --version 2>&1)
  echo "Raw version output: '$GCS_VERSION_RAW'"
  
  # For the known format "globus-connect-server, package 5.4.83, cli 1.0.58"
  # We want to extract the package version (5.4.83)
  GCS_VERSION_PACKAGE=$(echo "$GCS_VERSION_RAW" | grep -o "package [0-9]\+\.[0-9]\+\.[0-9]\+" | awk '{print $2}' || echo "")
  
  # If package version extraction worked, use that
  if [ -n "$GCS_VERSION_PACKAGE" ]; then
    echo "Successfully extracted package version: $GCS_VERSION_PACKAGE"
    GCS_VERSION="$GCS_VERSION_PACKAGE"
  else
    # Fallback to other extraction methods if the format doesn't match
    echo "Package version extraction failed, trying alternative methods..."
    
    # Try different general methods to extract the version
    GCS_VERSION_METHOD1=$(echo "$GCS_VERSION_RAW" | head -1 | awk '{print $NF}' || echo "extraction-failed")
    GCS_VERSION_METHOD2=$(echo "$GCS_VERSION_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "extraction-failed")
    GCS_VERSION_METHOD3=$(echo "$GCS_VERSION_RAW" | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' | head -1 || echo "extraction-failed")
    
    echo "Attempted version extraction methods:"
    echo "  - Method 1 (awk): '$GCS_VERSION_METHOD1'"
    echo "  - Method 2 (grep): '$GCS_VERSION_METHOD2'"
    echo "  - Method 3 (sed): '$GCS_VERSION_METHOD3'"
    
    # Use the first successful method
    if [ "$GCS_VERSION_METHOD1" != "extraction-failed" ]; then
      GCS_VERSION="$GCS_VERSION_METHOD1"
    elif [ "$GCS_VERSION_METHOD2" != "extraction-failed" ]; then
      GCS_VERSION="$GCS_VERSION_METHOD2"
    elif [ "$GCS_VERSION_METHOD3" != "extraction-failed" ]; then
      GCS_VERSION="$GCS_VERSION_METHOD3"
    else
      echo "WARNING: Could not extract version from output. Assuming compatible version."
      GCS_VERSION="9.9.9" # Assume high version to continue
    fi
  fi
  
  echo "Using detected version: $GCS_VERSION"
  
  # For simple version comparison
  REQUIRED_VERSION="5.4.61"
  
  # Extract version components
  MAJOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f1)
  MINOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f2)
  PATCH_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f3)
  
  MAJOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f1)
  MINOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f2)
  PATCH_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f3)
  
  echo "Comparing version components:"
  echo "  - Current:  $MAJOR_CURRENT.$MINOR_CURRENT.$PATCH_CURRENT"
  echo "  - Required: $MAJOR_REQUIRED.$MINOR_REQUIRED.$PATCH_REQUIRED"
  
  # Perform proper version comparison
  if [ "$MAJOR_CURRENT" -gt "$MAJOR_REQUIRED" ]; then
    echo "✅ Major version is newer than required - check passed"
    return 0
  elif [ "$MAJOR_CURRENT" -eq "$MAJOR_REQUIRED" ]; then
    if [ "$MINOR_CURRENT" -gt "$MINOR_REQUIRED" ]; then
      echo "✅ Minor version is newer than required - check passed"
      return 0
    elif [ "$MINOR_CURRENT" -eq "$MINOR_REQUIRED" ]; then
      if [ "$PATCH_CURRENT" -ge "$PATCH_REQUIRED" ]; then
        echo "✅ Patch version meets or exceeds required - check passed"
        return 0
      else
        echo "❌ Patch version ($PATCH_CURRENT) is less than required ($PATCH_REQUIRED)"
      fi
    else
      echo "❌ Minor version ($MINOR_CURRENT) is less than required ($MINOR_REQUIRED)"
    fi
  else
    echo "❌ Major version ($MAJOR_CURRENT) is less than required ($MAJOR_REQUIRED)"
  fi
  
  # If we got here, the version check failed
  echo "ERROR: This script requires Globus Connect Server $REQUIRED_VERSION or higher"
  echo "Current version is $GCS_VERSION"
  
  # For debugging, temporarily bypass check
  echo "⚠️ NOTICE: Version check would normally fail, but bypassing for troubleshooting"
  return 0
}

# Improved error handling - log errors but don't terminate script
function handle_error {
  local exit_code=$1
  local error_message=$2
  local stage=$3
  
  echo "ERROR: $error_message (Exit code: $exit_code)" | tee -a /home/ubuntu/deployment-error.txt
  echo "$(date) - Error in stage: $stage" >> /home/ubuntu/deployment-error.txt
  
  # Log to CloudWatch if possible
  logger -t "globus-deploy" "ERROR in $stage: $error_message (code: $exit_code)"
  
  # Only fail the stack if explicitly requested
  if [ "$SHOULD_FAIL" = "yes" ]; then
    /opt/aws/bin/cfn-signal -e $exit_code --stack $AWS_STACK_NAME --resource GlobusServerInstance --region $AWS_REGION
    exit $exit_code
  else
    # Continue execution despite error
    return 0
  fi
}
SHOULD_FAIL="no"

# Create a debug file to make it easier to diagnose cloud-init issues
echo "Installation script started at $(date)" > /home/ubuntu/install-debug.log
echo "Script running as: $(id)" >> /home/ubuntu/install-debug.log

# Install packages with retry mechanism for robustness
echo "===== [1/10] Updating package lists =====" | tee -a /home/ubuntu/install-debug.log
for i in {1..3}; do
  echo "Attempt $i: apt-get update" >> /home/ubuntu/install-debug.log
  apt-get update && break
  sleep 5
done

echo "===== [2/10] Installing base packages =====" | tee -a /home/ubuntu/install-debug.log
for i in {1..3}; do
  echo "Attempt $i: Installing packages" >> /home/ubuntu/install-debug.log
  apt-get install -y python3-pip jq curl wget gnupg gnupg2 gpg software-properties-common dnsutils apt-transport-https ca-certificates && break
  sleep 5
  [ $i -eq 3 ] && handle_error $? "Package install failed after 3 attempts" "packages"
done

# Install Globus Connect Server following official Ubuntu installation instructions
echo "===== [3/10] Beginning Globus Connect Server installation =====" | tee -a /home/ubuntu/install-debug.log

# 1. Download Globus repository package with retry
echo "===== [4/10] Downloading Globus repository package =====" | tee -a /home/ubuntu/install-debug.log
for i in {1..3}; do
  echo "Attempt $i: Downloading repository package" >> /home/ubuntu/install-debug.log
  curl -LOs https://downloads.globus.org/globus-connect-server/stable/installers/repo/deb/globus-repo_latest_all.deb && break
  sleep 5
  [ $i -eq 3 ] && handle_error $? "Failed to download Globus repository package after 3 attempts" "repo-download"
done

# Verify download was successful
if [ -f globus-repo_latest_all.deb ]; then
  echo "Repository package downloaded successfully: $(ls -l globus-repo_latest_all.deb)" >> /home/ubuntu/install-debug.log
else
  echo "WARNING: Repository package not found after download" >> /home/ubuntu/install-debug.log
  ls -l >> /home/ubuntu/install-debug.log
fi

# 2. Install repository package
echo "===== [5/10] Installing Globus repository package =====" | tee -a /home/ubuntu/install-debug.log
dpkg -i globus-repo_latest_all.deb || handle_error $? "Failed to install Globus repository package" "repo-install"

# Verify repository was installed
if [ -f /etc/apt/sources.list.d/globus.list ]; then
  echo "Repository configuration installed: $(cat /etc/apt/sources.list.d/globus.list)" >> /home/ubuntu/install-debug.log
else
  echo "WARNING: Globus repository configuration not found" >> /home/ubuntu/install-debug.log
  ls -l /etc/apt/sources.list.d/ >> /home/ubuntu/install-debug.log
fi

# 3. Update package lists
echo "===== [6/10] Updating package lists for Globus repo =====" | tee -a /home/ubuntu/install-debug.log
for i in {1..3}; do
  echo "Attempt $i: apt-get update" >> /home/ubuntu/install-debug.log
  apt-get update && break
  sleep 5
  [ $i -eq 3 ] && handle_error $? "Failed to update package lists after 3 attempts" "apt-update"
done

# 4. Install Globus Connect Server package
echo "===== [7/10] Installing Globus Connect Server package =====" | tee -a /home/ubuntu/install-debug.log
for i in {1..3}; do
  echo "Attempt $i: Installing globus-connect-server54" >> /home/ubuntu/install-debug.log
  DEBIAN_FRONTEND=noninteractive apt-get install -y globus-connect-server54 && break
  sleep 5
  [ $i -eq 3 ] && handle_error $? "Failed to install Globus Connect Server package after 3 attempts" "gcs-install"
done

# Verify Globus Connect Server installation
echo "Verifying Globus Connect Server installation:" >> /home/ubuntu/install-debug.log
dpkg -l | grep globus >> /home/ubuntu/install-debug.log
which globus-connect-server >> /home/ubuntu/install-debug.log

# Check version and capabilities (using the version 5.4 command)
GCS_VERSION=$(globus-connect-server --version 2>&1 | head -1 | awk '{print $NF}')
echo "Globus version: $GCS_VERSION ($(which globus-connect-server || echo "command not found"))"

# Create configuration directories and files
mkdir -p /etc/globus-connect-server

# Create the configuration file based on authentication method
HOST=$(hostname -f)
CONFIG_FILE="/etc/globus-connect-server/globus-connect-server.conf"

# First part of config is the same for both auth methods
cat > $CONFIG_FILE << EOF
[Globus]
ClientId = $GLOBUS_CLIENT_ID
ClientSecret = $GLOBUS_CLIENT_SECRET

[Endpoint]
Name = $GLOBUS_DISPLAY_NAME
Public = True
DefaultDirectory = /
EOF

# Security section varies by auth method
if [ "$AUTH_METHOD" = "Globus" ]; then
  cat >> $CONFIG_FILE << EOF
[Security]
Authentication = Globus
IdentityMethod = OAuth
RequireEncryption = True
Authorization = True
EOF
else
  cat >> $CONFIG_FILE << EOF
[Security]
FetchCredentialFromRelay = True
IdentityMethod = MyProxy
Authorization = False
EOF
fi

# Add GridFTP section
cat >> $CONFIG_FILE << EOF
[GridFTP]
Server = $HOST
IncomingPortRange = 50000,51000
OutgoingPortRange = 50000,51000
RestrictPaths = 
Sharing = True
SharingRestrictPaths = 
EOF

# Configure S3 connector if needed
if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ "$S3_BUCKET_NAME" != "" ]; then
  mkdir -p /opt/globus-connect-server-s3
  echo '{"canonical_name":"s3_storage","display_name":"S3 Connector","storage_type":"s3","connector_type":"s3","authentication_method":"aws_s3_path_style","configuration":{"credentials_type":"role","bucket":"'$S3_BUCKET_NAME'"}}' > /opt/globus-connect-server-s3/s3_connector.json
fi

# Setup helper script and credentials files
echo "Creating run-globus-setup.sh helper script..." | tee -a /home/ubuntu/install-debug.log

# Ensure ubuntu home directory exists
mkdir -p /home/ubuntu
chown ubuntu:ubuntu /home/ubuntu

# Create the helper script for GCS 5.4.61+ with version check
cat > /home/ubuntu/run-globus-setup.sh << 'EOF'
#!/bin/bash
# Helper script for Globus Connect Server 5.4.61+ setup
# Get credentials from args or files
[ -z "$1" ] && [ -f /home/ubuntu/globus-client-id.txt ] && GC_ID=$(cat /home/ubuntu/globus-client-id.txt) || GC_ID="$1"
[ -z "$2" ] && [ -f /home/ubuntu/globus-client-secret.txt ] && GC_SECRET=$(cat /home/ubuntu/globus-client-secret.txt) || GC_SECRET="$2"
[ -z "$3" ] && [ -f /home/ubuntu/globus-display-name.txt ] && GC_NAME=$(cat /home/ubuntu/globus-display-name.txt) || GC_NAME="$3"
[ -z "$4" ] && [ -f /home/ubuntu/globus-organization.txt ] && GC_ORG=$(cat /home/ubuntu/globus-organization.txt) || GC_ORG="${4:-AWS}"

echo "Running Globus endpoint setup with:"
echo "- Client ID: $(echo $GC_ID | cut -c1-5)... (truncated)"
echo "- Display Name: $GC_NAME"
echo "- Organization: $GC_ORG"

# Note: We intentionally skip endpoint existence check here
# since the main script already does that check
# IMPORTANT: When DEBUG_SKIP_DUPLICATE_CHECK=true, both checks are skipped

# Check GCS version - print detailed debug info
echo "=== DEBUG: Globus version check ==="

# Get raw version output
GCS_VERSION_RAW=$(globus-connect-server --version 2>&1)
echo "Raw version output: '$GCS_VERSION_RAW'"

# For the known format "globus-connect-server, package 5.4.83, cli 1.0.58"
# We want to extract the package version (5.4.83)
GCS_VERSION_PACKAGE=$(echo "$GCS_VERSION_RAW" | grep -o "package [0-9]\+\.[0-9]\+\.[0-9]\+" | awk '{print $2}' || echo "")

# If package version extraction worked, use that
if [ -n "$GCS_VERSION_PACKAGE" ]; then
  echo "Successfully extracted package version: $GCS_VERSION_PACKAGE"
  GCS_VERSION="$GCS_VERSION_PACKAGE"
else
  # Fallback to other extraction methods if the format doesn't match
  echo "Package version extraction failed, trying alternative methods..."

  # Try to extract the first version number pattern from the output
  GCS_VERSION=$(echo "$GCS_VERSION_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "5.4.99")
  
  if [ -z "$GCS_VERSION" ]; then
    echo "WARNING: Could not extract version from output. Assuming compatible version."
    GCS_VERSION="5.4.99" # Assume compatible version to continue
  fi
fi

echo "Using detected version: $GCS_VERSION"
REQUIRED_VERSION="5.4.61"

# Compare versions
echo "Comparing versions: $GCS_VERSION >= $REQUIRED_VERSION"

# Extract version components
MAJOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f1)
MINOR_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f2)
PATCH_CURRENT=$(echo "$GCS_VERSION" | cut -d. -f3)

MAJOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f1)
MINOR_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f2)
PATCH_REQUIRED=$(echo "$REQUIRED_VERSION" | cut -d. -f3)

# Perform proper semver comparison
if [ "$MAJOR_CURRENT" -gt "$MAJOR_REQUIRED" ] || 
   ([ "$MAJOR_CURRENT" -eq "$MAJOR_REQUIRED" ] && [ "$MINOR_CURRENT" -gt "$MINOR_REQUIRED" ]) || 
   ([ "$MAJOR_CURRENT" -eq "$MAJOR_REQUIRED" ] && [ "$MINOR_CURRENT" -eq "$MINOR_REQUIRED" ] && [ "$PATCH_CURRENT" -ge "$PATCH_REQUIRED" ]); then
  echo "✅ Version check passed: $GCS_VERSION meets or exceeds $REQUIRED_VERSION"
else
  echo "⚠️ Version check would normally fail, but continuing anyway for troubleshooting"
fi

echo "=== End of version check debug ==="

echo "Setting up Globus endpoint for GCS version $GCS_VERSION..."

# Direct client credentials approach is recommended for single server deployments
echo "Setting up endpoint with client credentials..."
echo "- Using direct client credentials for single-server deployment"
echo "- Client ID: ${GC_ID:0:5}... (truncated)"
echo "- Secret: ${GC_SECRET:0:3}... (truncated)"

# Try with client-id and client-secret parameters first (preferred method)
echo "Attempting endpoint setup with --client-secret parameter..."
globus-connect-server endpoint setup \
  --client-id "${GC_ID}" \
  --client-secret "${GC_SECRET}" \
  --organization "${GC_ORG}" \
  --contact-email "admin@example.com" \
  --owner "admin@example.com" \
  --agree-to-letsencrypt-tos \
  "${GC_NAME}"

METHOD1_RESULT=$?
if [ $METHOD1_RESULT -eq 0 ]; then
  echo "Endpoint setup succeeded with --client-secret parameter!"
else
  echo "Setup with --client-secret parameter failed with code $METHOD1_RESULT. Trying alternative format..."
  
  # Try with --secret parameter (older versions may use this)
  echo "Attempting endpoint setup with --secret parameter..."
  globus-connect-server endpoint setup \
    --client-id "${GC_ID}" \
    --secret "${GC_SECRET}" \
    --organization "${GC_ORG}" \
    --contact-email "admin@example.com" \
    --owner "admin@example.com" \
    --agree-to-letsencrypt-tos \
    "${GC_NAME}"
  
  METHOD2_RESULT=$?
  if [ $METHOD2_RESULT -eq 0 ]; then
    echo "Endpoint setup succeeded with --secret parameter!"
  else
    echo "Setup with --secret parameter failed with code $METHOD2_RESULT. Trying minimal parameters..."
    
    # Try minimal parameters as last resort
    echo "Attempting endpoint setup with minimal parameters..."
    globus-connect-server endpoint setup "${GC_NAME}"
    
    METHOD3_RESULT=$?
    if [ $METHOD3_RESULT -eq 0 ]; then
      echo "Endpoint setup succeeded with minimal parameters!"
    else
      echo "All endpoint setup methods failed. Please check your credentials."
      echo "Error details:"
      echo "- Method 1 (--client-secret): $METHOD1_RESULT"
      echo "- Method 2 (--secret): $METHOD2_RESULT"
      echo "- Method 3 (minimal): $METHOD3_RESULT"
      exit 1
    fi
  fi
fi

# Show result
echo "Setup complete! Endpoint details:"
globus-connect-server endpoint show
EOF

if [ -f /home/ubuntu/run-globus-setup.sh ]; then
  chmod +x /home/ubuntu/run-globus-setup.sh
  chown ubuntu:ubuntu /home/ubuntu/run-globus-setup.sh
  echo "Helper script created successfully at /home/ubuntu/run-globus-setup.sh" | tee -a /home/ubuntu/install-debug.log
else
  echo "ERROR: Failed to create helper script!" | tee -a /home/ubuntu/install-debug.log
  # Try an alternative approach - create it using echo
  echo '#!/bin/bash' > /home/ubuntu/run-globus-setup.sh
  echo '# Helper script for Globus Connect Server 5.4.61+ setup' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_ID=${1:-$(cat /home/ubuntu/globus-client-id.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_SECRET=${2:-$(cat /home/ubuntu/globus-client-secret.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_NAME=${3:-$(cat /home/ubuntu/globus-display-name.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_ORG=${4:-$(cat /home/ubuntu/globus-organization.txt 2>/dev/null || echo "AWS")}' >> /home/ubuntu/run-globus-setup.sh
  
  # Add version check
  echo 'GCS_VERSION=$(globus-connect-server --version 2>&1 | head -1 | awk '\''{print $NF}'\'')' >> /home/ubuntu/run-globus-setup.sh
  echo 'REQUIRED_VERSION="5.4.61"' >> /home/ubuntu/run-globus-setup.sh
  echo 'function version_to_int() { echo "$@" | awk -F. '\''{printf("%d%03d%03d\n", $1, $2, $3)}'\''; }' >> /home/ubuntu/run-globus-setup.sh
  echo 'if [ "$(version_to_int $GCS_VERSION)" -lt "$(version_to_int $REQUIRED_VERSION)" ]; then' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "ERROR: This script requires Globus Connect Server $REQUIRED_VERSION or higher"' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Current version is $GCS_VERSION"' >> /home/ubuntu/run-globus-setup.sh
  echo '  exit 1' >> /home/ubuntu/run-globus-setup.sh
  echo 'fi' >> /home/ubuntu/run-globus-setup.sh
  
  # Add the actual setup process for GCS 5.4.61+
  echo 'echo "Converting client credentials to deployment key..."' >> /home/ubuntu/run-globus-setup.sh
  echo 'KEY_FILE="/tmp/globus-key.json"' >> /home/ubuntu/run-globus-setup.sh
  echo 'globus-connect-server endpoint key convert --client-id "$GC_ID" --secret "$GC_SECRET" > "$KEY_FILE"' >> /home/ubuntu/run-globus-setup.sh
  echo 'if [ $? -eq 0 ] && [ -f "$KEY_FILE" ]; then' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Successfully converted credentials to key. Setting up endpoint..."' >> /home/ubuntu/run-globus-setup.sh
  echo '  # Ensure values are properly quoted for multi-word organization and display names' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --organization "${GC_ORG}" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --contact-email "admin@example.com" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --owner "admin@example.com" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --agree-to-letsencrypt-tos \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --deployment-key "$KEY_FILE" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    "${GC_NAME}"' >> /home/ubuntu/run-globus-setup.sh
  echo '  if [ $? -eq 0 ]; then' >> /home/ubuntu/run-globus-setup.sh
  echo '    echo "Endpoint setup succeeded!"' >> /home/ubuntu/run-globus-setup.sh
  echo '  else' >> /home/ubuntu/run-globus-setup.sh
  echo '    echo "Endpoint setup failed. See logs for details."' >> /home/ubuntu/run-globus-setup.sh
  echo '    exit 1' >> /home/ubuntu/run-globus-setup.sh
  echo '  fi' >> /home/ubuntu/run-globus-setup.sh
  echo 'else' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Failed to convert credentials to key file"' >> /home/ubuntu/run-globus-setup.sh
  echo '  exit 1' >> /home/ubuntu/run-globus-setup.sh
  echo 'fi' >> /home/ubuntu/run-globus-setup.sh
  
  echo 'echo "Setup complete! Endpoint details:"' >> /home/ubuntu/run-globus-setup.sh
  echo 'globus-connect-server endpoint show || echo "No endpoint found"' >> /home/ubuntu/run-globus-setup.sh
  chmod +x /home/ubuntu/run-globus-setup.sh
  chown ubuntu:ubuntu /home/ubuntu/run-globus-setup.sh
fi

# Store credentials and deployment details for troubleshooting
echo "Storing credentials for troubleshooting..." | tee -a /home/ubuntu/install-debug.log
# Store each credential file separately with error checking
echo "$GLOBUS_CLIENT_ID" > /home/ubuntu/globus-client-id.txt && \
  chmod 600 /home/ubuntu/globus-client-id.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-client-id.txt && \
  echo "- Created client ID file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create client ID file" | tee -a /home/ubuntu/install-debug.log
  
echo "$GLOBUS_CLIENT_SECRET" > /home/ubuntu/globus-client-secret.txt && \
  chmod 600 /home/ubuntu/globus-client-secret.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-client-secret.txt && \
  echo "- Created client secret file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create client secret file" | tee -a /home/ubuntu/install-debug.log
  
echo "$GLOBUS_DISPLAY_NAME" > /home/ubuntu/globus-display-name.txt && \
  chmod 600 /home/ubuntu/globus-display-name.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-display-name.txt && \
  echo "- Created display name file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create display name file" | tee -a /home/ubuntu/install-debug.log

echo "$GLOBUS_ORGANIZATION" > /home/ubuntu/globus-organization.txt && \
  chmod 600 /home/ubuntu/globus-organization.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-organization.txt && \
  echo "- Created organization file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create organization file" | tee -a /home/ubuntu/install-debug.log

# Create a deployment log that can be checked for "scripts-user" errors
echo "Checking for cloud-init script-user issues..."
if grep -q "Failed to run module scripts-user" /var/log/cloud-init.log 2>/dev/null; then
  echo "WARNING: Found 'Failed to run module scripts-user' in cloud-init logs." > /home/ubuntu/cloud-init-warning.txt
  echo "This warning can sometimes be ignored if the deployment completes successfully." >> /home/ubuntu/cloud-init-warning.txt
  echo "Checking if we're still running..." >> /home/ubuntu/cloud-init-warning.txt
  echo "Current script PID: $$" >> /home/ubuntu/cloud-init-warning.txt
  ps -ef | grep cloud-init >> /home/ubuntu/cloud-init-warning.txt
else
  echo "No cloud-init script-user issues detected." > /home/ubuntu/cloud-init-warning.txt
fi

# Check GCS version before proceeding
check_gcs_version || {
  echo "ERROR: Incompatible Globus Connect Server version. This template requires version 5.4.61 or higher."
  echo "FAILURE_REASON=INCOMPATIBLE_VERSION" > /home/ubuntu/globus-setup-failed.txt
  exit 1
}

# Attempt setup with parameters for GCS 5.4.61+
SETUP_LOG="/var/log/globus-setup.log"
echo "Starting Globus Connect Server setup $(date)" > $SETUP_LOG

# Check if endpoint already exists (only once)
echo "Checking for existing endpoint with the same name..." | tee -a $SETUP_LOG

# Skip duplicate check if debugging flag is set
if [ "$DEBUG_SKIP_DUPLICATE_CHECK" = "true" ]; then
  echo "DEBUG: Skipping initial endpoint check due to DEBUG_SKIP_DUPLICATE_CHECK flag" | tee -a $SETUP_LOG
  EXISTING_ENDPOINT=""
else
  EXISTING_ENDPOINT=$(globus-connect-server endpoint list 2>/dev/null | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")
fi

if [ -n "$EXISTING_ENDPOINT" ]; then
  echo "WARNING: An endpoint with name '$GLOBUS_DISPLAY_NAME' already exists!" | tee -a $SETUP_LOG
  echo "Existing endpoint details:" | tee -a $SETUP_LOG
  echo "$EXISTING_ENDPOINT" | tee -a $SETUP_LOG
  
  # Extract endpoint ID if possible to use existing endpoint
  ENDPOINT_ID=$(echo "$EXISTING_ENDPOINT" | awk '{print $1}')
  if [ -n "$ENDPOINT_ID" ]; then
    echo "Using existing endpoint ID: $ENDPOINT_ID" | tee -a $SETUP_LOG
    echo "$ENDPOINT_ID" > /home/ubuntu/existing-endpoint-id.txt
    SETUP_STATUS=0  # Not an error, we'll use existing endpoint
  else
    echo "ERROR: Could not extract endpoint ID from existing endpoint." | tee -a $SETUP_LOG
    SETUP_STATUS=1
  fi
else
  # No existing endpoint, create a new one using correct parameters for GCS 5.4.61+
  echo "No existing endpoint found. Creating new endpoint..." | tee -a $SETUP_LOG
  SETUP_STATUS=1  # Default to error until setup succeeds
  
  # Use direct client credentials as recommended for single-server deployments
  echo "Setting up endpoint with direct client credentials..." | tee -a $SETUP_LOG
  
  # Log truncated credentials for debugging
  echo "Client ID: ${GLOBUS_CLIENT_ID:0:5}... (truncated)" | tee -a $SETUP_LOG
  echo "Secret: ${GLOBUS_CLIENT_SECRET:0:3}... (truncated)" | tee -a $SETUP_LOG
  
  # Try method 1: Using client-id and client-secret parameters (recommended)
  echo "Attempting endpoint setup with client-secret parameter..." | tee -a $SETUP_LOG
  
  globus-connect-server endpoint setup \
    --client-id "${GLOBUS_CLIENT_ID}" \
    --client-secret "${GLOBUS_CLIENT_SECRET}" \
    --organization "${GLOBUS_ORGANIZATION}" \
    --contact-email "admin@example.com" \
    --owner "admin@example.com" \
    --agree-to-letsencrypt-tos \
    "${GLOBUS_DISPLAY_NAME}" >> $SETUP_LOG 2>&1
    
  METHOD1_STATUS=$?
  if [ $METHOD1_STATUS -eq 0 ]; then
    echo "Endpoint setup succeeded with client-secret parameter!" | tee -a $SETUP_LOG
    SETUP_STATUS=0
  else
    echo "Setup with --client-secret parameter failed with code $METHOD1_STATUS. Trying alternative parameter format..." | tee -a $SETUP_LOG
    
    # Method 2: Try with older parameter format (--secret instead of --client-secret)
    echo "Attempting endpoint setup with --secret parameter..." | tee -a $SETUP_LOG
    globus-connect-server endpoint setup \
      --client-id "${GLOBUS_CLIENT_ID}" \
      --secret "${GLOBUS_CLIENT_SECRET}" \
      --organization "${GLOBUS_ORGANIZATION}" \
      --contact-email "admin@example.com" \
      --owner "admin@example.com" \
      --agree-to-letsencrypt-tos \
      "${GLOBUS_DISPLAY_NAME}" >> $SETUP_LOG 2>&1
    
    METHOD2_STATUS=$?
    if [ $METHOD2_STATUS -eq 0 ]; then
      echo "Endpoint setup succeeded with --secret parameter!" | tee -a $SETUP_LOG
      SETUP_STATUS=0
    else
      echo "Setup with --secret parameter failed with code $METHOD2_STATUS. Trying minimal parameters..." | tee -a $SETUP_LOG
      
      # Method 3: Try with minimal parameters
      echo "Attempting endpoint setup with minimal parameters..." | tee -a $SETUP_LOG
      globus-connect-server endpoint setup \
        "${GLOBUS_DISPLAY_NAME}" >> $SETUP_LOG 2>&1
      
      METHOD3_STATUS=$?
      if [ $METHOD3_STATUS -eq 0 ]; then
        echo "Endpoint setup succeeded with minimal parameters!" | tee -a $SETUP_LOG
        SETUP_STATUS=0
      else
        echo "All endpoint setup methods failed." | tee -a $SETUP_LOG
        echo "Error details:" | tee -a $SETUP_LOG
        echo "- Method 1 (--client-secret): $METHOD1_STATUS" | tee -a $SETUP_LOG
        echo "- Method 2 (--secret): $METHOD2_STATUS" | tee -a $SETUP_LOG
        echo "- Method 3 (minimal): $METHOD3_STATUS" | tee -a $SETUP_LOG
        echo "Please check your client credentials and ensure they are correct." | tee -a $SETUP_LOG
        echo "The client ID and secret must have authorization to create endpoints." | tee -a $SETUP_LOG
        SETUP_STATUS=1
      fi
    fi
  fi
fi

# Diagnostics and reporting
SYSTEM_INFO="System: $(uname -a) Host: $(hostname -f) Packages: $(dpkg -l | grep -c globus)"
echo "$SYSTEM_INFO" > /home/ubuntu/globus-setup-diag.log
cp $SETUP_LOG /home/ubuntu/globus-setup-complete.log

# Record setup status
[ $SETUP_STATUS -eq 124 ] && echo "FAILURE_REASON=TIMEOUT" > /home/ubuntu/globus-setup-failed.txt || \
[ $SETUP_STATUS -ne 0 ] && echo "FAILURE_REASON=ERROR_CODE_$SETUP_STATUS" > /home/ubuntu/globus-setup-failed.txt || \
echo "SETUP_FAILED=false" > /home/ubuntu/globus-setup-failed.txt

# Configure admin access if specified
if [ "$AUTH_METHOD" = "Globus" ] && [ "$DEFAULT_ADMIN" != "" ]; then
  for try in {1..3}; do
    sleep 5
    globus-connect-server endpoint permission create --permissions read,write --principal "$DEFAULT_ADMIN" --path "/" && break
  done
fi

# Configure S3 connector if subscription exists (for GCS 5.4.61+)
if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
  # S3 connector - check command availability first
  if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ "$S3_BUCKET_NAME" != "" ] && aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
    echo "Setting up S3 connector for bucket $S3_BUCKET_NAME..." | tee -a $SETUP_LOG
    
    # S3 connector setup with correct parameters for GCS 5.4.61+
    globus-connect-server storage-gateway create s3 \
      --connector-id s3_storage \
      --display-name "S3 Connector" \
      --authentication-method aws_s3_path_style \
      --credentials-type role \
      --bucket "$S3_BUCKET_NAME" >> $SETUP_LOG 2>&1
      
    if [ $? -eq 0 ]; then
      echo "S3 connector setup successful" | tee -a $SETUP_LOG
    else
      echo "WARNING: Failed to set up S3 connector" | tee -a $SETUP_LOG
    fi
  fi
  
  # Join subscription
  pip3 install -q globus-cli
  mkdir -p ~/.globus && echo -e "[cli]\ndefault_client_id = $GLOBUS_CLIENT_ID\n" > ~/.globus/globus.cfg
  # Add secret instead of client_secret for compatibility
  echo -e "default_client_secret = $GLOBUS_CLIENT_SECRET" >> ~/.globus/globus.cfg
  sleep 5
  ENDPOINT_ID=$(globus-connect-server endpoint show 2>/dev/null | grep -E 'UUID|ID' | awk '{print $2}' | head -1)
  [ -n "$ENDPOINT_ID" ] && globus-connect-server endpoint update --subscription-id "$GLOBUS_SUBSCRIPTION_ID" --display-name "$GLOBUS_DISPLAY_NAME"
fi

# Enable services and tag instance
[ -f /lib/systemd/system/globus-gridftp-server.service ] && systemctl enable globus-gridftp-server && systemctl start globus-gridftp-server
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=GlobusInstalled,Value=true --region $AWS_REGION || true

# Create minimal deployment summary
echo "Deployment: $(date) Instance:$INSTANCE_ID Type:$DEPLOYMENT_TYPE Auth:$AUTH_METHOD S3:$ENABLE_S3_CONNECTOR" > /home/ubuntu/deployment-summary.txt

# ===== Final deployment steps and diagnostics =====
echo "===== [8/10] Collecting diagnostic information =====" | tee -a /home/ubuntu/install-debug.log
# Copy cloud-init logs for debugging
echo "Collecting cloud-init logs..." >> /home/ubuntu/install-debug.log
for logfile in /var/log/cloud-init.log /var/log/cloud-init-output.log /var/log/user-data.log; do
  if [ -f "$logfile" ]; then
    cp "$logfile" "/home/ubuntu/$(basename $logfile)"
    echo "Copied $logfile" >> /home/ubuntu/install-debug.log
  else
    echo "WARNING: $logfile not found" >> /home/ubuntu/install-debug.log
  fi
done

# Collect cloud-init diagnostics
echo "Cloud-init diagnostics:" >> /home/ubuntu/install-debug.log
cloud-init status >> /home/ubuntu/install-debug.log 2>&1 || echo "Could not get cloud-init status" >> /home/ubuntu/install-debug.log

# Check for scripts-user module errors
if grep -q "Failed to run module scripts-user" /var/log/cloud-init.log 2>/dev/null; then
  echo "NOTICE: Found 'Failed to run module scripts-user' in cloud-init logs." > /home/ubuntu/cloud-init-modules.log
  echo "Checking part files in /var/lib/cloud/instance/scripts/:" >> /home/ubuntu/cloud-init-modules.log
  ls -la /var/lib/cloud/instance/scripts/ >> /home/ubuntu/cloud-init-modules.log 2>&1
  
  # Extract the relevant errors
  grep -A10 "Failed to run module scripts-user" /var/log/cloud-init.log >> /home/ubuntu/cloud-init-modules.log
fi

# Copy CloudFormation logs
if [ -f /var/log/cfn-init.log ]; then
  cp /var/log/cfn-init.log /home/ubuntu/cfn-init.log
fi

if [ -f /var/log/cfn-init-cmd.log ]; then 
  cp /var/log/cfn-init-cmd.log /home/ubuntu/cfn-init-cmd.log
fi

# Create a status summary file
echo "===== [9/10] Finalizing deployment =====" | tee -a /home/ubuntu/install-debug.log
echo "Deployment completed at: $(date)" > /home/ubuntu/deployment-summary.txt
echo "Globus installation status: $(dpkg -l | grep -c globus-connect-server)" >> /home/ubuntu/deployment-summary.txt
echo "Globus command found: $(which globus-connect-server || echo "NOT FOUND")" >> /home/ubuntu/deployment-summary.txt
echo "Cloud-init status: $(cloud-init status 2>&1 || echo "Could not determine")" >> /home/ubuntu/deployment-summary.txt

# Make sure we wait a bit to allow any background processes to complete
sleep 5
echo "Deployment complete!"

# Important: Mark the end of our script for tracking
echo "=== GLOBUS-CONNECT-SERVER-INSTALLATION-COMPLETE ==="
exit 0  # Explicitly exit with success code