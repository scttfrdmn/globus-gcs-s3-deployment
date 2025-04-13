#!/bin/bash
# Full Globus Connect Server installation script
# This script is designed to be downloaded and executed from S3
# Will use environment variables passed from the CloudFormation bootstrap script

# Setup proper logging - using both file and console output
exec > >(tee /var/log/globus-setup.log|logger -t globus-setup -s 2>/dev/console) 2>&1

# Mark the beginning of our script for tracking
echo "=== GLOBUS-CONNECT-SERVER-INSTALLATION-SCRIPT ==="

echo "=== Starting Globus Connect Server installation $(date) ==="
echo "Stack:$AWS_STACK_NAME Region:$AWS_REGION Type:$DEPLOYMENT_TYPE Auth:$AUTH_METHOD"
echo "S3 Connector: $ENABLE_S3_CONNECTOR Bucket: $S3_BUCKET_NAME"

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

# Create the helper script with error checking
cat > /home/ubuntu/run-globus-setup.sh << 'EOF'
#!/bin/bash
# Get credentials from args or files
[ -z "$1" ] && [ -f /home/ubuntu/globus-client-id.txt ] && GC_ID=$(cat /home/ubuntu/globus-client-id.txt) || GC_ID="$1"
[ -z "$2" ] && [ -f /home/ubuntu/globus-client-secret.txt ] && GC_SECRET=$(cat /home/ubuntu/globus-client-secret.txt) || GC_SECRET="$2"
[ -z "$3" ] && [ -f /home/ubuntu/globus-display-name.txt ] && GC_NAME=$(cat /home/ubuntu/globus-display-name.txt) || GC_NAME="$3"
[ -z "$4" ] && [ -f /home/ubuntu/globus-organization.txt ] && GC_ORG=$(cat /home/ubuntu/globus-organization.txt) || GC_ORG="${4:-AWS}"

echo "Running Globus endpoint setup with:"
echo "- Client ID: $(echo $GC_ID | cut -c1-5)... (truncated)"
echo "- Display Name: $GC_NAME"
echo "- Organization: $GC_ORG"

echo "Setting up Globus endpoint..."
# Try all versions in sequence, starting with the modern format

# Try modern format first (with positional DISPLAY_NAME argument)
echo "Trying modern Globus Connect Server format (positional display name)..."
globus-connect-server endpoint setup \
  --organization "$GC_ORG" \
  --contact-email "admin@example.com" \
  --owner "admin@example.com" \
  --yes \
  "$GC_NAME"

# If the modern format fails, try older formats
if [ $? -ne 0 ]; then
  echo "Modern setup failed, trying alternative methods..."
  
  # Check if we need to convert client credentials to a key
  if globus-connect-server endpoint key convert --help &>/dev/null; then
    echo "Trying to convert client credentials to a deployment key..."
    KEY_FILE="/tmp/globus-key.json"
    
    # Convert client ID/secret to a key file
    if globus-connect-server endpoint key convert --help 2>/dev/null | grep -q -- "--output"; then
      # Use --output if supported
      globus-connect-server endpoint key convert \
        --client-id "$GC_ID" \
        --secret "$GC_SECRET" \
        --output "$KEY_FILE"
    else
      # Otherwise, redirect output to the key file
      globus-connect-server endpoint key convert \
        --client-id "$GC_ID" \
        --secret "$GC_SECRET" > "$KEY_FILE"
    fi
    
    if [ $? -eq 0 ] && [ -f "$KEY_FILE" ]; then
      echo "Successfully converted credentials to key. Trying setup with deployment key..."
      globus-connect-server endpoint setup \
        --organization "$GC_ORG" \
        --contact-email "admin@example.com" \
        --owner "admin@example.com" \
        --yes \
        --deployment-key "$KEY_FILE" \
        "$GC_NAME"
    else
      echo "Failed to convert credentials to key file"
    fi
  else
    # Fall back to older formats if key convert is not available
    echo "Key conversion not available, trying older command formats..."
    
    # Try with --secret parameter
    echo "Trying with --secret parameter..."
    globus-connect-server endpoint setup \
      --client-id "$GC_ID" \
      --secret "$GC_SECRET" \
      --name "$GC_NAME" \
      --organization "$GC_ORG"
    
    # If that fails too, try with --client-secret parameter
    if [ $? -ne 0 ]; then
      echo "Trying with --client-secret parameter..."
      globus-connect-server endpoint setup \
        --client-id "$GC_ID" \
        --client-secret "$GC_SECRET" \
        --name "$GC_NAME" \
        --organization "$GC_ORG"
      
      # Last attempt with minimal parameters
      if [ $? -ne 0 ]; then
        echo "Trying with minimal parameters..."
        globus-connect-server endpoint setup \
          --client-id "$GC_ID" \
          --secret "$GC_SECRET"
      fi
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
  echo '# Manual setup script for Globus' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_ID=${1:-$(cat /home/ubuntu/globus-client-id.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_SECRET=${2:-$(cat /home/ubuntu/globus-client-secret.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_NAME=${3:-$(cat /home/ubuntu/globus-display-name.txt 2>/dev/null)}' >> /home/ubuntu/run-globus-setup.sh
  echo 'GC_ORG=${4:-$(cat /home/ubuntu/globus-organization.txt 2>/dev/null || echo "AWS")}' >> /home/ubuntu/run-globus-setup.sh
  echo 'echo "Trying modern format first..."' >> /home/ubuntu/run-globus-setup.sh
  echo 'globus-connect-server endpoint setup --organization "$GC_ORG" --contact-email "admin@example.com" --owner "admin@example.com" --yes "$GC_NAME" || \\' >> /home/ubuntu/run-globus-setup.sh
  echo 'if globus-connect-server endpoint key convert --help &>/dev/null; then \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Converting client credentials to deployment key..." && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  KEY_FILE="/tmp/globus-key.json" && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  if globus-connect-server endpoint key convert --help 2>/dev/null | grep -q -- "--output"; then \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    globus-connect-server endpoint key convert --client-id "$GC_ID" --secret "$GC_SECRET" --output "$KEY_FILE"; \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  else \\' >> /home/ubuntu/run-globus-setup.sh
  echo '    globus-connect-server endpoint key convert --client-id "$GC_ID" --secret "$GC_SECRET" > "$KEY_FILE"; \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  fi && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  [ -f "$KEY_FILE" ] && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup --organization "$GC_ORG" --contact-email "admin@example.com" --owner "admin@example.com" --yes --deployment-key "$KEY_FILE" "$GC_NAME" \\' >> /home/ubuntu/run-globus-setup.sh
  echo 'else \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Trying legacy format with --secret parameter..." && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup --client-id "$GC_ID" --secret "$GC_SECRET" --name "$GC_NAME" --organization "$GC_ORG" || \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Trying legacy format with --client-secret parameter..." && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup --client-id "$GC_ID" --client-secret "$GC_SECRET" --name "$GC_NAME" --organization "$GC_ORG" || \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  echo "Trying minimal parameters..." && \\' >> /home/ubuntu/run-globus-setup.sh
  echo '  globus-connect-server endpoint setup --client-id "$GC_ID" --secret "$GC_SECRET" \\' >> /home/ubuntu/run-globus-setup.sh
  echo 'fi' >> /home/ubuntu/run-globus-setup.sh
  echo 'echo "Setup complete (or failed). Endpoint details:"' >> /home/ubuntu/run-globus-setup.sh
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

# Attempt setup with appropriate method
SETUP_LOG="/var/log/globus-setup.log"
echo "Starting Globus Connect Server setup $(date)" > $SETUP_LOG

# Check if endpoint already exists (only once)
echo "Checking for existing endpoint with the same name..." | tee -a $SETUP_LOG
EXISTING_ENDPOINT=$(globus-connect-server endpoint list 2>/dev/null | grep -F "$GLOBUS_DISPLAY_NAME" || echo "")

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
  # No existing endpoint, create a new one
  echo "No existing endpoint found. Creating new endpoint..." | tee -a $SETUP_LOG
  SETUP_STATUS=1  # Default to error until one command succeeds
  
  # Try modern format first (with positional DISPLAY_NAME argument and different parameters)
  # Add --yes to accept the Let's Encrypt Terms of Service automatically
  echo "Trying setup with modern Globus Connect Server format (positional display name)..." | tee -a $SETUP_LOG
  globus-connect-server endpoint setup \
    --organization "$GLOBUS_ORGANIZATION" \
    --contact-email "admin@example.com" \
    --owner "admin@example.com" \
    --yes \
    "$GLOBUS_DISPLAY_NAME" >> $SETUP_LOG 2>&1
  
  if [ $? -eq 0 ]; then
    echo "Modern setup command succeeded!" | tee -a $SETUP_LOG
    SETUP_STATUS=0
  else
    # If modern format fails, fall back to older versions
    echo "Modern setup failed, trying older command formats..." | tee -a $SETUP_LOG
    
    # Check if we need to convert the client ID/secret to a key first
    echo "Checking if we need to convert client credentials to a key..." | tee -a $SETUP_LOG
    if globus-connect-server endpoint key convert --help &>/dev/null; then
      echo "Found endpoint key convert command, trying to convert credentials..." | tee -a $SETUP_LOG
      
      # Create temporary key file
      KEY_FILE="/tmp/globus-key.json"
      # Check if --output is supported
      if globus-connect-server endpoint key convert --help 2>/dev/null | grep -q -- "--output"; then
        # Use --output if supported
        globus-connect-server endpoint key convert \
          --client-id "$GLOBUS_CLIENT_ID" \
          --secret "$GLOBUS_CLIENT_SECRET" \
          --output "$KEY_FILE" >> $SETUP_LOG 2>&1
      else
        # Otherwise, redirect output to the key file
        globus-connect-server endpoint key convert \
          --client-id "$GLOBUS_CLIENT_ID" \
          --secret "$GLOBUS_CLIENT_SECRET" > "$KEY_FILE" 2>> $SETUP_LOG
      fi
      
      if [ $? -eq 0 ] && [ -f "$KEY_FILE" ]; then
        echo "Successfully converted credentials to key file. Trying setup with key..." | tee -a $SETUP_LOG
        globus-connect-server endpoint setup \
          --organization "$GLOBUS_ORGANIZATION" \
          --contact-email "admin@example.com" \
          --owner "admin@example.com" \
          --yes \
          --deployment-key "$KEY_FILE" \
          "$GLOBUS_DISPLAY_NAME" >> $SETUP_LOG 2>&1
        
        if [ $? -eq 0 ]; then
          echo "Setup with deployment key succeeded!" | tee -a $SETUP_LOG
          SETUP_STATUS=0
        else
          echo "Setup with deployment key failed!" | tee -a $SETUP_LOG
        fi
      else
        echo "Failed to convert credentials to key file" | tee -a $SETUP_LOG
      fi
    else
      # Fall back to older methods if key convert is not available
      # Try older format with minimal parameters
      echo "Trying older format with minimal parameters..." | tee -a $SETUP_LOG
      globus-connect-server endpoint setup \
        --client-id "$GLOBUS_CLIENT_ID" \
        --secret "$GLOBUS_CLIENT_SECRET" >> $SETUP_LOG 2>&1
      
      if [ $? -eq 0 ]; then
        echo "Setup with minimal parameters succeeded!" | tee -a $SETUP_LOG
        SETUP_STATUS=0
      else
        # Try with --name parameter
        echo "Trying setup with --name parameter..." | tee -a $SETUP_LOG
        globus-connect-server endpoint setup \
          --client-id "$GLOBUS_CLIENT_ID" \
          --secret "$GLOBUS_CLIENT_SECRET" \
          --name "$GLOBUS_DISPLAY_NAME" >> $SETUP_LOG 2>&1
        
        if [ $? -eq 0 ]; then
          echo "Setup with --name parameter succeeded!" | tee -a $SETUP_LOG
          SETUP_STATUS=0
        else
          # Try with --name and --organization parameters
          echo "Trying setup with --name and --organization parameters..." | tee -a $SETUP_LOG
          globus-connect-server endpoint setup \
            --client-id "$GLOBUS_CLIENT_ID" \
            --secret "$GLOBUS_CLIENT_SECRET" \
            --name "$GLOBUS_DISPLAY_NAME" \
            --organization "$GLOBUS_ORGANIZATION" >> $SETUP_LOG 2>&1
          
          if [ $? -eq 0 ]; then
            echo "Setup with --name and --organization parameters succeeded!" | tee -a $SETUP_LOG
            SETUP_STATUS=0
          else
            # Last attempt with client_secret instead of secret
            echo "Trying setup with --client-secret parameter..." | tee -a $SETUP_LOG
            globus-connect-server endpoint setup \
              --client-id "$GLOBUS_CLIENT_ID" \
              --client-secret "$GLOBUS_CLIENT_SECRET" \
              --name "$GLOBUS_DISPLAY_NAME" \
              --organization "$GLOBUS_ORGANIZATION" >> $SETUP_LOG 2>&1
            
            if [ $? -eq 0 ]; then
              echo "Setup with --client-secret parameter succeeded!" | tee -a $SETUP_LOG
              SETUP_STATUS=0
            else
              echo "All setup attempts failed!" | tee -a $SETUP_LOG
            fi
          fi
        fi
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

# Configure S3 connector if subscription exists
if [ -n "$GLOBUS_SUBSCRIPTION_ID" ]; then
  # S3 connector - check command availability first
  if [ "$ENABLE_S3_CONNECTOR" = "true" ] && [ "$S3_BUCKET_NAME" != "" ] && aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
    # Check if the command supports storage-gateway
    if globus-connect-server help 2>&1 | grep -q "storage-gateway"; then
      globus-connect-server storage-gateway create --connector-id s3_storage --display-name "S3 Connector" \
        --connector-type s3 --authentication-method aws_s3_path_style --credentials-type role --bucket $S3_BUCKET_NAME
    else
      echo "WARNING: This version of Globus does not support the storage-gateway command" | tee -a $SETUP_LOG
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