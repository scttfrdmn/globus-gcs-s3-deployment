#!/bin/bash
# Script to collect diagnostic information for debugging

DIAG_DIR="/home/ubuntu/diagnostics"
mkdir -p "$DIAG_DIR"

echo "Collecting diagnostic information to $DIAG_DIR..."

# Copy logs
echo "Copying logs..."
cp /var/log/cloud-init-output.log "$DIAG_DIR/" 2>/dev/null || echo "Could not copy cloud-init-output.log"
cp /var/log/globus-setup.log "$DIAG_DIR/" 2>/dev/null || echo "Could not copy globus-setup.log"
cp /home/ubuntu/globus-setup-output.log "$DIAG_DIR/" 2>/dev/null || echo "Could not copy globus-setup-output.log"
cp /home/ubuntu/debug.log "$DIAG_DIR/" 2>/dev/null || echo "Could not copy debug.log"
cp /home/ubuntu/setup-error.log "$DIAG_DIR/" 2>/dev/null || echo "Could not copy setup-error.log"
cp /home/ubuntu/endpoint-setup-output.txt "$DIAG_DIR/" 2>/dev/null || echo "Could not copy endpoint-setup-output.txt"
cp /home/ubuntu/*FAILED.txt "$DIAG_DIR/" 2>/dev/null || echo "No failure files found"

# System information
echo "Collecting system information..."
echo "--- Date/Time ---" > "$DIAG_DIR/system-info.txt"
date >> "$DIAG_DIR/system-info.txt"
echo -e "\n--- Disk Space ---" >> "$DIAG_DIR/system-info.txt"
df -h >> "$DIAG_DIR/system-info.txt"
echo -e "\n--- Memory ---" >> "$DIAG_DIR/system-info.txt"
free -h >> "$DIAG_DIR/system-info.txt"
echo -e "\n--- Network ---" >> "$DIAG_DIR/system-info.txt"
ifconfig >> "$DIAG_DIR/system-info.txt" 2>/dev/null || ip addr >> "$DIAG_DIR/system-info.txt"
echo -e "\n--- Environment Variables ---" >> "$DIAG_DIR/system-info.txt"
env | grep -i "GLOBUS\|S3\|AWS\|GCS\|ENDPOINT" >> "$DIAG_DIR/system-info.txt"

# Globus specific information
echo "Collecting Globus information..."
if command -v globus-connect-server &>/dev/null; then
  echo "--- Globus Version ---" > "$DIAG_DIR/globus-info.txt"
  globus-connect-server --version >> "$DIAG_DIR/globus-info.txt" 2>&1
  echo -e "\n--- Globus Services Status ---" >> "$DIAG_DIR/globus-info.txt"
  systemctl status globus-* >> "$DIAG_DIR/globus-info.txt" 2>&1 || echo "Could not get service status" >> "$DIAG_DIR/globus-info.txt"
  echo -e "\n--- Globus Configuration ---" >> "$DIAG_DIR/globus-info.txt"
  ls -la /etc/globus-connect-server/ >> "$DIAG_DIR/globus-info.txt" 2>&1 || echo "No configuration directory found" >> "$DIAG_DIR/globus-info.txt"
else
  echo "Globus Connect Server not installed or not in PATH" > "$DIAG_DIR/globus-info.txt"
fi

# File permissions
echo "Checking file permissions..."
echo "--- Home Directory Permissions ---" > "$DIAG_DIR/file-permissions.txt"
ls -la /home/ubuntu/ >> "$DIAG_DIR/file-permissions.txt"

# Package status
echo "Checking installed packages..."
echo "--- Installed Globus Packages ---" > "$DIAG_DIR/package-info.txt"
dpkg -l | grep -i globus >> "$DIAG_DIR/package-info.txt" 2>&1

# Create a README
cat > "$DIAG_DIR/README.txt" << 'EOF'
Globus Connect Server Deployment Diagnostics
===========================================

This directory contains diagnostic information collected to help troubleshoot
issues with the Globus Connect Server deployment. Key files include:

- globus-setup.log: Main log file from the setup script
- cloud-init-output.log: AWS instance initialization log
- debug.log: Detailed debug logging from the setup script
- endpoint-setup-output.txt: Output from the endpoint setup command
- system-info.txt: System information (disk, memory, network)
- globus-info.txt: Globus-specific information and configuration
- file-permissions.txt: File and directory permissions
- package-info.txt: Information about installed packages

To analyze these files, look for ERROR or WARNING entries, 
check service statuses, and verify that all required packages are installed.
EOF

# Fix permissions
chmod -R 755 "$DIAG_DIR"
chown -R ubuntu:ubuntu "$DIAG_DIR"

echo "Diagnostics collection complete. Files are in: $DIAG_DIR"