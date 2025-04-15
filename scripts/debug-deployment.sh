#!/bin/bash
# Script to help diagnose deployment failures

echo "Running deployment diagnostics..."

# Collect logs and diagnostics
if [ -f /home/ubuntu/collect-diagnostics.sh ]; then
  echo "Running diagnostics collection script..."
  bash /home/ubuntu/collect-diagnostics.sh
fi

# Try sourcing the setup-env script to load variables
if [ -f /home/ubuntu/setup-env.sh ]; then
  echo "Sourcing setup-env.sh to set environment variables..."
  source /home/ubuntu/setup-env.sh
fi

echo "Diagnostics complete. Check /home/ubuntu/diagnostics/ directory for detailed logs."
echo "To manually run Globus commands, first run: source /home/ubuntu/setup-env.sh"