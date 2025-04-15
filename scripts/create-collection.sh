#!/bin/bash
# Script to help with collection creation and permissions for Globus Connect Server

# Load environment variables
if [ -f /home/ubuntu/setup-env.sh ]; then
  source /home/ubuntu/setup-env.sh
else
  echo "Error: environment setup script not found. Please run this from an instance with a deployed Globus Connect Server."
  exit 1
fi

# Make sure we have an endpoint ID
if [ -z "$GCS_CLI_ENDPOINT_ID" ]; then
  echo "Error: No endpoint ID found. Please make sure this is run on a properly configured Globus Connect Server."
  exit 1
fi

# Function to display help
show_help() {
  echo "Globus Collection Helper Script"
  echo "==============================="
  echo "This script helps you create collections and set permissions for your Globus Connect Server."
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help             Show this help message"
  echo "  -l, --list-gateways    List available storage gateways"
  echo "  -c, --create-collection GATEWAY_ID NAME  Create a collection for a storage gateway"
  echo "  -p, --permissions COLLECTION_ID IDENTITY Set permissions for a collection"
  echo "  -s, --show-collections List existing collections"
  echo ""
  echo "Examples:"
  echo "  $0 --list-gateways                       Show available storage gateways"
  echo "  $0 --create-collection abc123 \"My Data\"  Create a collection on gateway abc123"
  echo "  $0 --permissions def456 user@example.edu Give read/write access to a user"
  echo "  $0 --show-collections                    List existing collections"
}

# Function to list storage gateways
list_gateways() {
  echo "Listing available storage gateways..."
  globus-connect-server storage-gateway list
}

# Function to create a collection
create_collection() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Gateway ID and display name required"
    echo "Usage: $0 --create-collection GATEWAY_ID \"Display Name\""
    exit 1
  fi
  
  gateway_id="$1"
  display_name="$2"
  
  echo "Creating collection \"$display_name\" for gateway $gateway_id..."
  globus-connect-server collection create --storage-gateway "$gateway_id" --display-name "$display_name"
  
  if [ $? -eq 0 ]; then
    echo "Collection created successfully!"
    echo "You can now set permissions for this collection."
    echo "First, get the collection ID with: $0 --show-collections"
    echo "Then set permissions with: $0 --permissions COLLECTION_ID IDENTITY"
  else
    echo "Failed to create collection."
  fi
}

# Function to set permissions on a collection
set_permissions() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Collection ID and identity required"
    echo "Usage: $0 --permissions COLLECTION_ID user@example.edu"
    exit 1
  fi
  
  collection_id="$1"
  identity="$2"
  
  echo "Setting read/write permissions for $identity on collection $collection_id..."
  globus-connect-server endpoint permission create --identity "$identity" --permissions rw --collection "$collection_id"
  
  if [ $? -eq 0 ]; then
    echo "Permissions set successfully!"
  else
    echo "Failed to set permissions."
  fi
}

# Function to list collections
show_collections() {
  echo "Listing collections for endpoint $GCS_CLI_ENDPOINT_ID..."
  globus-connect-server collection list
}

# Parse command line arguments
if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -l|--list-gateways)
      list_gateways
      exit 0
      ;;
    -c|--create-collection)
      if [ -z "$2" ] || [ -z "$3" ]; then
        echo "Error: Gateway ID and display name required"
        exit 1
      fi
      create_collection "$2" "$3"
      exit 0
      ;;
    -p|--permissions)
      if [ -z "$2" ] || [ -z "$3" ]; then
        echo "Error: Collection ID and identity required"
        exit 1
      fi
      set_permissions "$2" "$3"
      exit 0
      ;;
    -s|--show-collections)
      show_collections
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
  shift
done