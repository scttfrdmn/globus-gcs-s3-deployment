# Creating and Managing Globus Groups via CLI

Globus Groups are managed through the Globus CLI, which provides commands to create, update, and manage group membership. Here's how to work with Globus Groups via the command line:

## Prerequisites

1. Install the Globus CLI (if not already installed):

   ```bash
   pip install globus-cli
   ```

2. Authenticate with Globus:

   ```bash
   globus login
   ```

## Creating a New Globus Group

```bash
# Basic group creation
globus group create "My Team Group"

# Create with description
globus group create "Research Lab Access" --description "Access group for lab members"

# Create with specific visibility (default is "private")
globus group create "Department Collaborators" --visibility private|authenticated|public
```

The command will return a group ID that looks like: `a1b2c3d4-5678-90ef-ghij-klmnopqrstuv`

## Managing Group Membership

### Add Members to the Group

```bash
# Add a member with default access_level (member)
globus group member add GROUP_ID user@example.org

# Add with specific access level
globus group member add GROUP_ID user@example.org --role admin
```

Valid roles include:

- `admin` - Can manage group membership and settings
- `manager` - Can add/remove members
- `member` - Basic access

### Add Multiple Members at Once

```bash
# Create a members file
cat > members.txt << EOF
user1@example.org,member
user2@example.org,manager
user3@example.org,admin
EOF

# Add members from file
cat members.txt | while IFS=, read user role; do
  globus group member add GROUP_ID $user --role $role
done
```

### List Group Members

```bash
# List all members
globus group member list GROUP_ID

# Get formatted output
globus group member list GROUP_ID --format JSON
```

### Remove Members

```bash
# Remove a member
globus group member remove GROUP_ID user@example.org
```

## Managing Groups

### List Your Groups

```bash
# List groups you're a member of
globus group list

# List groups you administer
globus group list --role admin
```

### Get Group Details

```bash
# Show group information
globus group show GROUP_ID
```

### Update Group Information

```bash
# Update group name
globus group update GROUP_ID --name "New Group Name"

# Update description
globus group update GROUP_ID --description "Updated group description"

# Update visibility
globus group update GROUP_ID --visibility authenticated
```

### Delete a Group

```bash
# Delete a group (requires admin role)
globus group delete GROUP_ID
```

## Using Groups with Globus Connect Server Access Controls

Once you've created a group, you can use it in your GCS access policies:

```bash
# Get your group ID
GROUP_ID=$(globus group list --format JSON | jq -r '.[] | select(.name=="My Team Group") | .id')

# Grant access to the group on your endpoint
globus-connect-server acl create \
  --permissions read,write \
  --principal "urn:globus:groups:id:${GROUP_ID}" \
  --path "/s3_storage/shared-data/"
```

## Creating a Group with Initial Members (Script Example)

Here's a complete script to create a group and add initial members:

```bash
#!/bin/bash
# create_research_group.sh

# Create the group
echo "Creating research group..."
GROUP_ID=$(globus group create "Research Project Alpha" \
  --description "Research team access for Project Alpha" \
  --format JSON | jq -r '.id')

echo "Group created with ID: $GROUP_ID"

# Add members
echo "Adding members..."
# Admin access
globus group member add $GROUP_ID "lead@example.org" --role admin

# Manager access
globus group member add $GROUP_ID "coordinator@example.org" --role manager

# Regular members
for member in "researcher1@example.org" "researcher2@example.org" "assistant@example.org"; do
  globus group member add $GROUP_ID $member --role member
done

echo "Group setup complete!"
```

This approach allows you to efficiently manage access to your Globus collections by managing group membership rather than individual access policies on your endpoints.