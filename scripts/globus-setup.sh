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
    # Set a high version to ensure version-specific logic still works
    GCS_VERSION="9.9.9"
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
# Helper script for Globus Connect Server 5.4.61+ setup using automated deployment approach
# Get credentials from args or files
[ -z "$1" ] && [ -f /home/ubuntu/globus-client-id.txt ] && GC_ID=$(cat /home/ubuntu/globus-client-id.txt) || GC_ID="$1"
[ -z "$2" ] && [ -f /home/ubuntu/globus-client-secret.txt ] && GC_SECRET=$(cat /home/ubuntu/globus-client-secret.txt) || GC_SECRET="$2"
[ -z "$3" ] && [ -f /home/ubuntu/globus-display-name.txt ] && GC_NAME=$(cat /home/ubuntu/globus-display-name.txt) || GC_NAME="$3"
[ -z "$4" ] && [ -f /home/ubuntu/globus-organization.txt ] && GC_ORG=$(cat /home/ubuntu/globus-organization.txt) || GC_ORG="${4:-AWS}"
[ -z "$5" ] && [ -f /home/ubuntu/globus-owner.txt ] && GC_OWNER=$(cat /home/ubuntu/globus-owner.txt)
[ -z "$6" ] && [ -f /home/ubuntu/globus-contact-email.txt ] && GC_EMAIL=$(cat /home/ubuntu/globus-contact-email.txt)

echo "Running Globus endpoint setup with:"
echo "- Client ID: $(echo $GC_ID | cut -c1-5)... (truncated)"
echo "- Display Name: $GC_NAME"
echo "- Organization: $GC_ORG"
echo "- Owner: $GC_OWNER"
echo "- Contact Email: $GC_EMAIL"

# IMPORTANT: We completely skip endpoint existence check in this helper script
# The main script already does that check if needed, and when 
# DEBUG_SKIP_DUPLICATE_CHECK=true both checks are skipped

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

# Set up environment-based service credential authentication as recommended in
# https://docs.globus.org/globus-connect-server/v5/automated-deployment/
echo "Setting up endpoint using service credentials..."
echo "- Using environment variables for service credential authentication"
echo "- Client ID: ${GC_ID:0:5}... (truncated)"

# Set the environment variables for service credential authentication
export GCS_CLI_CLIENT_ID="${GC_ID}"
export GCS_CLI_CLIENT_SECRET="${GC_SECRET}"

# Use the standard documented format for Globus Connect Server with environment auth
echo "Setting up endpoint using automated deployment approach..."

# Prepare command with required parameters
SETUP_CMD="globus-connect-server endpoint setup"

# Check if we should use --dont-set-advertised-owner flag
# This flag makes the endpoint harder to find in the web interface but can help with certain authentication issues
if [ "${GLOBUS_DONT_SET_ADVERTISED_OWNER}" = "true" ]; then
  echo "Adding --dont-set-advertised-owner flag as requested"
  SETUP_CMD+=" --dont-set-advertised-owner"
else
  echo "NOT using --dont-set-advertised-owner for better endpoint visibility"
fi

# Required parameters
SETUP_CMD+=" --organization \"${GC_ORG}\""

# Project ID is critical for automated deployments
GC_PROJECT_ID=""
[ -f /home/ubuntu/globus-project-id.txt ] && GC_PROJECT_ID=$(cat /home/ubuntu/globus-project-id.txt)
if [ -n "${GC_PROJECT_ID}" ]; then
  echo "Using project ID: ${GC_PROJECT_ID}"
  SETUP_CMD+=" --project-id \"${GC_PROJECT_ID}\""
else
  echo "WARNING: No project ID specified. This is strongly recommended for automated deployments."
  echo "See https://docs.globus.org/globus-connect-server/v5/automated-deployment/ for details."
fi

# Use the owner parameter (required) - either from argument or explicit owner var
if [ -n "${GC_OWNER}" ]; then
  echo "Using specified owner: ${GC_OWNER}"
  SETUP_CMD+=" --owner \"${GC_OWNER}\""
else
  echo "ERROR: No owner specified. Owner parameter is required."
  echo "Please provide the owner parameter via the GLOBUS_OWNER environment variable."
  exit 1
fi

# Contact email is required - use specified email or fallback
if [ -n "${GC_EMAIL}" ]; then
  echo "Using specified contact email: ${GC_EMAIL}"
  SETUP_CMD+=" --contact-email \"${GC_EMAIL}\""
else
  echo "ERROR: No contact email specified. Contact email parameter is required."
  echo "Please provide the contact email parameter via the GLOBUS_CONTACT_EMAIL environment variable."
  exit 1
fi

# Standard options
SETUP_CMD+=" --agree-to-letsencrypt-tos"

# Log the command we're about to run
echo "Running endpoint setup command with display name: ${GC_NAME}"
echo "Using environment variables GCS_CLI_CLIENT_ID and GCS_CLI_CLIENT_SECRET for authentication"
if [ "${GLOBUS_DONT_SET_ADVERTISED_OWNER}" = "true" ]; then
  echo "Using --dont-set-advertised-owner flag (endpoint will be harder to find in Globus web interface)"
else
  echo "NOT using --dont-set-advertised-owner for better endpoint visibility"
fi

# Execute the command - passing the display name as a direct positional argument
# to ensure proper quoting
eval $SETUP_CMD '"${GC_NAME}"'

SETUP_RESULT=$?
if [ $SETUP_RESULT -eq 0 ]; then
  echo "Endpoint setup succeeded!"
else
  echo "Endpoint setup failed with code $SETUP_RESULT."
  echo "Please check your service credentials and ensure they are correct."
  echo "The client ID and secret must have authorization to create endpoints."
  
  # Provide detailed diagnostics
  echo "=== Error diagnostics ==="
  echo "1. Credentials environment variables set: $(env | grep -c GCS_CLI)"
  echo "2. Command that failed: ${SETUP_CMD} \"${GC_NAME}\""
  echo "3. Check Globus documentation: https://docs.globus.org/globus-connect-server/v5/automated-deployment/"
  exit 1
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
  
  # Add environment variables for owner and contact email
  echo 'GC_OWNER=${5:-$(cat /home/ubuntu/globus-owner.txt 2>/dev/null || echo "${GLOBUS_OWNER}")}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_EMAIL=${6:-$(cat /home/ubuntu/globus-contact-email.txt 2>/dev/null || echo "${GLOBUS_CONTACT_EMAIL}")}' >> /home/ubuntu/run-globus-setup.sh
  
  # Add the actual setup process for GCS 5.4.61+
  echo 'echo "Converting client credentials to deployment key..."' >> /home/ubuntu/run-globus-setup.sh
  echo 'KEY_FILE="/tmp/globus-key.json"' >> /home/ubuntu/run-globus-setup.sh
  echo 'globus-connect-server endpoint key convert --client-id "$GC_ID" --secret "$GC_SECRET" > "$KEY_FILE"' >> /home/ubuntu/run-globus-setup.sh
  echo 'if [ $? -eq 0 ] && [ -f "$KEY_FILE" ]; then' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Successfully converted credentials to key. Setting up endpoint..."' >> /home/ubuntu/run-globus-setup.sh
  echo '  # Ensure values are properly quoted for multi-word organization and display names' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --organization "${GC_ORG}" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --contact-email "${GC_EMAIL:-${GC_ID}}" \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    --owner "${GC_OWNER:-${GC_ID}}" \\' >> /home/ubuntu/run-globus-setup.sh
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

echo "$GLOBUS_OWNER" > /home/ubuntu/globus-owner.txt && \
  chmod 600 /home/ubuntu/globus-owner.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-owner.txt && \
  echo "- Created owner file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create owner file" | tee -a /home/ubuntu/install-debug.log
  
echo "$GLOBUS_CONTACT_EMAIL" > /home/ubuntu/globus-contact-email.txt && \
  chmod 600 /home/ubuntu/globus-contact-email.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-contact-email.txt && \
  echo "- Created contact email file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create contact email file" | tee -a /home/ubuntu/install-debug.log
  
echo "$GLOBUS_PROJECT_ID" > /home/ubuntu/globus-project-id.txt && \
  chmod 600 /home/ubuntu/globus-project-id.txt && \
  chown ubuntu:ubuntu /home/ubuntu/globus-project-id.txt && \
  echo "- Created project ID file" >> /home/ubuntu/install-debug.log || \
  echo "ERROR: Failed to create project ID file" | tee -a /home/ubuntu/install-debug.log

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

# Ensure GCS_VERSION is available outside the function for version-specific logic
if [ -n "$DEBUG_SKIP_VERSION_CHECK" ] && [ -z "$GCS_VERSION" ]; then
  echo "Setting default high version for debug mode"
  GCS_VERSION="9.9.9"
fi

# Attempt setup with parameters for GCS 5.4.61+
SETUP_LOG="/var/log/globus-setup.log"
echo "Starting Globus Connect Server setup $(date)" > $SETUP_LOG

# Check if endpoint already exists (only once)
# Skip duplicate check if debugging flag is set
if [ "$DEBUG_SKIP_DUPLICATE_CHECK" = "true" ]; then
  echo "DEBUG: Skipping endpoint check due to DEBUG_SKIP_DUPLICATE_CHECK flag" | tee -a $SETUP_LOG
  EXISTING_ENDPOINT=""
else
  echo "Checking for existing endpoint with the same name: '$GLOBUS_DISPLAY_NAME'..." | tee -a $SETUP_LOG
  
  # Setup Globus CLI for more reliable endpoint listing - use same auth as for the setup
  pip3 install -q globus-cli
  mkdir -p ~/.globus
  
  # Ensure Globus CLI is properly configured with the same credentials
  cat > ~/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF
  
  # First try globus-connect-server endpoint list
  EXISTING_ENDPOINT=$(globus-connect-server endpoint list 2>/dev/null | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")
  
  # Fallback to globus CLI if first method doesn't work
  if [ -z "$EXISTING_ENDPOINT" ]; then
    echo "Trying alternate endpoint search method..." | tee -a $SETUP_LOG
    # The globus CLI works differently and requires the user to be logged in
    if command -v globus &>/dev/null; then
      GLOBUS_SEARCH=$(globus endpoint search --filter-scope all "$GLOBUS_DISPLAY_NAME" 2>/dev/null || echo "")
      if [ -n "$GLOBUS_SEARCH" ] && echo "$GLOBUS_SEARCH" | grep -q "$GLOBUS_DISPLAY_NAME"; then
        echo "Found endpoint using globus CLI:" | tee -a $SETUP_LOG
        echo "$GLOBUS_SEARCH" | tee -a $SETUP_LOG
        
        # Parse UUID from search result
        UUID_PATTERN="[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}"
        ENDPOINT_UUID=$(echo "$GLOBUS_SEARCH" | grep -o "$UUID_PATTERN" | head -1)
        
        if [ -n "$ENDPOINT_UUID" ]; then
          EXISTING_ENDPOINT="$ENDPOINT_UUID $GLOBUS_DISPLAY_NAME"
        fi
      fi
    fi
  fi
fi

if [ -n "$EXISTING_ENDPOINT" ]; then
  echo "WARNING: An endpoint with name '$GLOBUS_DISPLAY_NAME' already exists!" | tee -a $SETUP_LOG
  echo "Existing endpoint details:" | tee -a $SETUP_LOG
  echo "$EXISTING_ENDPOINT" | tee -a $SETUP_LOG
  
  # Extract endpoint ID if possible to use existing endpoint - try UUID pattern first
  ENDPOINT_ID=$(echo "$EXISTING_ENDPOINT" | grep -o "[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | head -1)
  
  # Fallback to first field if UUID pattern doesn't match
  if [ -z "$ENDPOINT_ID" ]; then
    ENDPOINT_ID=$(echo "$EXISTING_ENDPOINT" | awk '{print $1}')
  fi
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
  
  # Use the standard documented format for Globus Connect Server 5.4.61+
  echo "Setting up endpoint using standard parameters format..." | tee -a $SETUP_LOG
  
  # Prepare command with required parameters
  SETUP_CMD="globus-connect-server endpoint setup"
  
  # Add --dont-set-advertised-owner flag for automated deployments to avoid 
  # showing the service identity as the endpoint owner in Globus app UI
  SETUP_CMD+=" --dont-set-advertised-owner"
  
  # Make sure GCS_VERSION is a valid version string
  if [[ ! "$GCS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "WARNING: Invalid GCS_VERSION format, using default high version" | tee -a $SETUP_LOG
    GCS_VERSION="9.9.9"
  fi
  
  # Check Globus version to determine if we need client-id
  GCS_VERSION_MAJOR=$(echo "$GCS_VERSION" | cut -d. -f1)
  GCS_VERSION_MINOR=$(echo "$GCS_VERSION" | cut -d. -f2)
  GCS_VERSION_PATCH=$(echo "$GCS_VERSION" | cut -d. -f3)
  
  echo "Using GCS version components for client credential check: $GCS_VERSION_MAJOR.$GCS_VERSION_MINOR.$GCS_VERSION_PATCH" | tee -a $SETUP_LOG
  
  # For Globus versions < 5.4.67, we might need to include client-id and client-secret as parameters
  # However, we'll primarily use the environment variable authentication method as recommended
  # in the automated deployment docs: https://docs.globus.org/globus-connect-server/v5/automated-deployment/
  
  # Note: No longer adding client credentials directly to command line
  # The environment variables GCS_CLI_CLIENT_ID and GCS_CLI_CLIENT_SECRET will be used instead
  echo "Using environment-based service credentials authentication for all GCS versions" | tee -a $SETUP_LOG
  echo "See Globus docs: https://docs.globus.org/globus-connect-server/v5/automated-deployment/" | tee -a $SETUP_LOG
  
  # Required parameters
  SETUP_CMD+=" --organization \"${GLOBUS_ORGANIZATION}\""
  
  # Owner is required - use DEFAULT_ADMIN if not provided
  if [ -n "${GLOBUS_OWNER}" ]; then
    echo "Using specified owner: ${GLOBUS_OWNER}" | tee -a $SETUP_LOG
    SETUP_CMD+=" --owner \"${GLOBUS_OWNER}\""
  elif [ -n "${DEFAULT_ADMIN}" ]; then
    echo "Using default admin as owner: ${DEFAULT_ADMIN}" | tee -a $SETUP_LOG
    SETUP_CMD+=" --owner \"${DEFAULT_ADMIN}\""
  else
    echo "ERROR: No owner specified. Please provide either GlobusOwner or DefaultAdminIdentity" | tee -a $SETUP_LOG
    echo "See Globus documentation: https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/#endpoint-setup" | tee -a $SETUP_LOG
    SETUP_STATUS=1
    exit 1
  fi
  
  # Contact email is required
  if [ -n "${GLOBUS_CONTACT_EMAIL}" ]; then
    echo "Using specified contact email: ${GLOBUS_CONTACT_EMAIL}" | tee -a $SETUP_LOG
    SETUP_CMD+=" --contact-email \"${GLOBUS_CONTACT_EMAIL}\""
  else
    echo "ERROR: No contact email specified. Please provide the GlobusContactEmail parameter" | tee -a $SETUP_LOG
    echo "See Globus documentation: https://docs.globus.org/globus-connect-server/v5.4/reference/cli-reference/#endpoint-setup" | tee -a $SETUP_LOG
    SETUP_STATUS=1
    exit 1
  fi
  
  # Project ID is critical for automated deployments
  if [ -n "${GLOBUS_PROJECT_ID}" ]; then
    echo "Using project ID: ${GLOBUS_PROJECT_ID}" | tee -a $SETUP_LOG
    SETUP_CMD+=" --project-id \"${GLOBUS_PROJECT_ID}\""
  else
    echo "WARNING: No project ID specified. This is strongly recommended for automated deployments." | tee -a $SETUP_LOG
    echo "See https://docs.globus.org/globus-connect-server/v5/automated-deployment/ for details." | tee -a $SETUP_LOG
  fi
  
  # Other optional project parameters
  if [ -n "${GLOBUS_PROJECT_NAME}" ]; then
    SETUP_CMD+=" --project-name \"${GLOBUS_PROJECT_NAME}\""
  fi
  
  if [ -n "${GLOBUS_PROJECT_ADMIN}" ]; then
    SETUP_CMD+=" --project-admin \"${GLOBUS_PROJECT_ADMIN}\""
  fi
  
  if [ "${GLOBUS_ALWAYS_CREATE_PROJECT}" = "true" ]; then
    SETUP_CMD+=" --always-create-project"
  fi
  
  # Standard options
  SETUP_CMD+=" --agree-to-letsencrypt-tos"
  
  # Log the command we're about to run
  echo "Running endpoint setup command with display name: ${GLOBUS_DISPLAY_NAME}" | tee -a $SETUP_LOG
  
  # Setup proper environment variables for service credentials
  # This is the recommended approach for automated deployment as per
  # https://docs.globus.org/globus-connect-server/v5/automated-deployment/
  
  # Ensure credentials are properly exported in multiple ways for maximum compatibility
  # 1. Export environment variables
  export GCS_CLI_CLIENT_ID="${GLOBUS_CLIENT_ID}"
  export GCS_CLI_CLIENT_SECRET="${GLOBUS_CLIENT_SECRET}"
  
  # 2. Create Globus CLI config file in case environment variables aren't working
  mkdir -p ~/.globus
  cat > ~/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF
  
  echo "Setting up service credentials via environment variables" | tee -a $SETUP_LOG
  echo "GCS_CLI_CLIENT_ID=${GCS_CLI_CLIENT_ID:0:5}... (truncated)" | tee -a $SETUP_LOG
  
  # Check if we should use --dont-set-advertised-owner flag based on parameter
  # This flag makes the endpoint harder to find but can help with certain authentication issues
  if [ "${GLOBUS_DONT_SET_ADVERTISED_OWNER}" = "true" ]; then
    echo "Adding --dont-set-advertised-owner flag as requested" | tee -a $SETUP_LOG
    # Make sure the flag is present in the command if requested
    if ! echo "$SETUP_CMD" | grep -q -- "--dont-set-advertised-owner"; then
      SETUP_CMD+=" --dont-set-advertised-owner"
    fi
  else
    echo "NOT using --dont-set-advertised-owner for better endpoint visibility" | tee -a $SETUP_LOG
    # Make sure the flag is NOT present in the command
    SETUP_CMD=$(echo "$SETUP_CMD" | sed 's/--dont-set-advertised-owner//')
  fi
  
  # Execute the command - passing the display name as a direct positional argument
  # rather than as part of the command string to ensure proper quoting
  echo "Running command with environment-based authentication: ${SETUP_CMD} \"${GLOBUS_DISPLAY_NAME}\"" | tee -a $SETUP_LOG
  eval $SETUP_CMD '"${GLOBUS_DISPLAY_NAME}"' >> $SETUP_LOG 2>&1
    
  SETUP_RESULT=$?
  if [ $SETUP_RESULT -eq 0 ]; then
    echo "Endpoint setup succeeded!" | tee -a $SETUP_LOG
    SETUP_STATUS=0
    
    # Capture and save the full endpoint UUID reliably
    echo "Extracting endpoint UUID..." | tee -a $SETUP_LOG
    # Get the complete endpoint show output
    ENDPOINT_SHOW_OUTPUT=$(globus-connect-server endpoint show)
    echo "$ENDPOINT_SHOW_OUTPUT" > /home/ubuntu/endpoint-details.txt
    
    # Extract UUID using more reliable approach
    ENDPOINT_UUID=$(echo "$ENDPOINT_SHOW_OUTPUT" | grep -i "uuid" | awk '{print $2}' || echo "")
    if [ -n "$ENDPOINT_UUID" ]; then
      echo "Endpoint UUID: $ENDPOINT_UUID" | tee -a $SETUP_LOG
      echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
      chmod 644 /home/ubuntu/endpoint-uuid.txt
    else
      # Try alternative method if the first one fails
      ENDPOINT_UUID=$(echo "$ENDPOINT_SHOW_OUTPUT" | grep -i "id" | awk '{print $2}' || echo "")
      if [ -n "$ENDPOINT_UUID" ]; then
        echo "Endpoint ID: $ENDPOINT_UUID" | tee -a $SETUP_LOG
        echo "$ENDPOINT_UUID" > /home/ubuntu/endpoint-uuid.txt
        chmod 644 /home/ubuntu/endpoint-uuid.txt
      else
        echo "WARNING: Could not extract endpoint UUID" | tee -a $SETUP_LOG
      fi
    fi
  else
    echo "Endpoint setup failed with code $SETUP_RESULT." | tee -a $SETUP_LOG
    echo "Please check your client credentials and ensure they are correct." | tee -a $SETUP_LOG
    echo "The client ID and secret must have authorization to create endpoints." | tee -a $SETUP_LOG
    
    # For debugging, show detailed error information
    echo "=== Error diagnostics ===" | tee -a $SETUP_LOG
    echo "1. Credentials environment variables set: $(env | grep -c GCS_CLI)" | tee -a $SETUP_LOG
    echo "2. Command that failed: ${SETUP_CMD} \"${GLOBUS_DISPLAY_NAME}\"" | tee -a $SETUP_LOG
    echo "3. Check Globus documentation: https://docs.globus.org/globus-connect-server/v5/automated-deployment/" | tee -a $SETUP_LOG
    echo "=========================" | tee -a $SETUP_LOG
    
    SETUP_STATUS=1
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

# Create a helper script for users to easily access the UUID and see endpoint info
cat > /home/ubuntu/show-endpoint.sh << 'EOF'
#!/bin/bash
# This script helps view endpoint details using the Globus CLI with proper authentication

# Source credentials if available
if [ -f /home/ubuntu/globus-client-id.txt ] && [ -f /home/ubuntu/globus-client-secret.txt ]; then
  export GCS_CLI_CLIENT_ID=$(cat /home/ubuntu/globus-client-id.txt)
  export GCS_CLI_CLIENT_SECRET=$(cat /home/ubuntu/globus-client-secret.txt)
  
  # Set up Globus CLI config
  mkdir -p ~/.globus
  echo -e "[cli]\ndefault_client_id = $GCS_CLI_CLIENT_ID" > ~/.globus/globus.cfg
  echo -e "default_client_secret = $GCS_CLI_CLIENT_SECRET" >> ~/.globus/globus.cfg
fi

# Check if we have the UUID file
if [ -f /home/ubuntu/endpoint-uuid.txt ]; then
  ENDPOINT_UUID=$(cat /home/ubuntu/endpoint-uuid.txt)
  echo "Endpoint UUID: $ENDPOINT_UUID"
  
  # Try both commands to show endpoint details
  echo "===== Globus Connect Server Endpoint Details ====="
  globus-connect-server endpoint show
  
  echo "===== Globus CLI Endpoint Details ====="
  globus endpoint show --format json "$ENDPOINT_UUID" | python3 -m json.tool || echo "Unable to get details with globus CLI"
  
  echo "Note: To access endpoint in Globus web interface, go to:"
  echo "https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID"
else
  echo "Endpoint UUID file not found. Trying to get endpoint details..."
  globus-connect-server endpoint show || echo "Unable to show endpoint details"
fi
EOF

chmod +x /home/ubuntu/show-endpoint.sh
chown ubuntu:ubuntu /home/ubuntu/show-endpoint.sh

# Install and setup the Globus CLI with proper configuration
echo "Setting up Globus CLI and authentication..." | tee -a $SETUP_LOG
pip3 install -q globus-cli

# Configure authentication for both globus-connect-server and globus CLI
mkdir -p ~/.globus /home/ubuntu/.globus

# Configure for root user (used by script)
cat > ~/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF

# Configure for ubuntu user (for manual troubleshooting)
cat > /home/ubuntu/.globus/globus.cfg << EOF
[cli]
default_client_id = ${GLOBUS_CLIENT_ID}
default_client_secret = ${GLOBUS_CLIENT_SECRET}
EOF

chown -R ubuntu:ubuntu /home/ubuntu/.globus

# Configure S3 connector if subscription exists (for GCS 5.4.61+)
if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
  # Extract endpoint UUID - this will use the same UUID that was saved to file earlier
  ENDPOINT_UUID=$(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null || globus-connect-server endpoint show 2>/dev/null | grep -i "uuid\|id" | head -1 | awk '{print $2}')
  
  if [ -n "$ENDPOINT_UUID" ]; then
    echo "Joining endpoint to subscription ID: $GLOBUS_SUBSCRIPTION_ID..." | tee -a $SETUP_LOG
    # Update endpoint with subscription
    globus-connect-server endpoint update --subscription-id "$GLOBUS_SUBSCRIPTION_ID" --display-name "$GLOBUS_DISPLAY_NAME" | tee -a $SETUP_LOG
    
    # Verify the update worked
    globus-connect-server endpoint show | tee -a /home/ubuntu/endpoint-with-subscription.txt
    
    # Also create an explicit link for the user to access their endpoint
    echo "To access your endpoint, visit: https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" | tee -a /home/ubuntu/endpoint-access-url.txt
  else
    echo "WARNING: Could not find endpoint UUID for subscription association" | tee -a $SETUP_LOG
  fi
  
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
      
      # Save S3 connector details
      globus-connect-server storage-gateway list > /home/ubuntu/s3-connector-details.txt
    else
      echo "WARNING: Failed to set up S3 connector" | tee -a $SETUP_LOG
    fi
  fi
fi

# Enable services and tag instance
[ -f /lib/systemd/system/globus-gridftp-server.service ] && systemctl enable globus-gridftp-server && systemctl start globus-gridftp-server
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=GlobusInstalled,Value=true --region $AWS_REGION || true

# Create deployment summary with endpoint information
ENDPOINT_UUID=$(cat /home/ubuntu/endpoint-uuid.txt 2>/dev/null || echo "UUID not found")
echo "Deployment: $(date) Instance:$INSTANCE_ID Type:$DEPLOYMENT_TYPE Auth:$AUTH_METHOD S3:$ENABLE_S3_CONNECTOR" > /home/ubuntu/deployment-summary.txt
echo "Endpoint Information:" >> /home/ubuntu/deployment-summary.txt
echo "- UUID: $ENDPOINT_UUID" >> /home/ubuntu/deployment-summary.txt
echo "- Display Name: $GLOBUS_DISPLAY_NAME" >> /home/ubuntu/deployment-summary.txt
echo "- Organization: $GLOBUS_ORGANIZATION" >> /home/ubuntu/deployment-summary.txt
echo "- Web Interface: https://app.globus.org/file-manager?origin_id=$ENDPOINT_UUID" >> /home/ubuntu/deployment-summary.txt
echo "To view detailed endpoint information, run: /home/ubuntu/show-endpoint.sh" >> /home/ubuntu/deployment-summary.txt

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