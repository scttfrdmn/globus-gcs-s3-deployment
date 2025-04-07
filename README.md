# Deploying Globus Connect Server with S3 Connector on AWS

## Prerequisites

1. AWS Account and Permissions:

   - IAM permissions for CloudFormation, EC2, S3, IAM
   - EC2 key pair for SSH access
   - Existing VPC with public subnet (internet access required)

2. Globus Account and Registration:

   - Create account at [globus.org](https://www.globus.org/)
   - Register application in [Globus Developer Console](https://developers.globus.org/)
   - Obtain Client ID and Client Secret
   - (Optional) Obtain Subscription ID for connector support

3. S3 Storage:

   - Create S3 bucket or identify existing bucket
   - Note the bucket name

## Template Options

### Deployment Type

- **Integration**: Dynamic IP, suitable for testing
- **Production**: Includes Elastic IP, better for stable endpoints

### Authentication

- **Globus**: Federation-based auth (recommended)
- **MyProxy**: Local account-based auth (legacy)

### Connectors (require subscription)

- **S3 Connector**: Connect to S3 bucket
- **POSIX Connector**: Access local filesystem
- **Google Drive Connector**: Connect to Google Drive

### Network Options

- **VPC**: Where to deploy the server
- **Subnet**: Requires public internet access
- **Availability Zone**: Single AZ deployment
- **Force Elastic IP**: Optional static IP for integration deployments

## Deployment Steps

### 1. Prepare parameters file

```json
[
  {
    "ParameterKey": "DeploymentType",
    "ParameterValue": "Production"
  },
  {
    "ParameterKey": "InstanceType",
    "ParameterValue": "m6i.xlarge"
  },
  {
    "ParameterKey": "KeyName",
    "ParameterValue": "your-key-pair"
  },
  {
    "ParameterKey": "AvailabilityZone",
    "ParameterValue": "us-east-1a"
  },
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "vpc-xxxxxxxx"
  },
  {
    "ParameterKey": "SubnetId",
    "ParameterValue": "subnet-xxxxxxxx"
  },
  {
    "ParameterKey": "AuthenticationMethod",
    "ParameterValue": "Globus"
  },
  {
    "ParameterKey": "DefaultAdminIdentity",
    "ParameterValue": "your-email@example.org"
  },
  {
    "ParameterKey": "GlobusClientId",
    "ParameterValue": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusClientSecret",
    "ParameterValue": "xxxxxxxxxxxxxxxxxxxx"
  },
  {
    "ParameterKey": "GlobusDisplayName",
    "ParameterValue": "Your-Globus-Endpoint"
  },
  {
    "ParameterKey": "GlobusSubscriptionId",
    "ParameterValue": "xxxxxxxxxxxx"
  },
  {
    "ParameterKey": "EnableS3Connector",
    "ParameterValue": "true"
  },
  {
    "ParameterKey": "S3BucketName",
    "ParameterValue": "your-globus-bucket"
  },
  {
    "ParameterKey": "EnablePosixConnector",
    "ParameterValue": "false"
  },
  {
    "ParameterKey": "EnableGoogleDriveConnector",
    "ParameterValue": "false"
  }
]
```

### 2. Deploy the CloudFormation stack

​	The cloudformation template is at the end of this document.

```bash
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM
```

### 3. Monitor deployment

```bash
# Check stack creation status
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].StackStatus"

# Wait for complete status
aws cloudformation wait stack-create-complete --stack-name globus-gcs
```

## Verification Steps

### 1. Retrieve stack outputs

```bash
aws cloudformation describe-stacks --stack-name globus-gcs --query "Stacks[0].Outputs"
```

Key outputs include:

- InstanceId
- ElasticIP or PublicIP
- PublicAddress (for Globus redirection)
- AuthenticationConfiguration
- ConnectorsEnabled

### 2. SSH into the instance

```bash
# Get the public address
PUBLIC_DNS=$(aws cloudformation describe-stacks --stack-name globus-gcs \
  --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text)

# Connect via SSH
ssh -i your-key-pair.pem ec2-user@$PUBLIC_DNS
```

### 3. Check Globus installation

```bash
# Check server status
systemctl status globus-gridftp-server

# Show endpoint details
globus-connect-server endpoint show

# List configured connectors
globus-connect-server storage-gateway list
```

### 4. Verify access policies (if using Globus auth)

```bash
# List access policies
globus-connect-server acl list
```

### 6. Verify through Globus web interface

1. Go to [app.globus.org](https://app.globus.org/)
2. Log in with your Globus account
3. Navigate to "Collections" > "Your Collections"
4. Find your endpoint name
5. Confirm you can browse and transfer files

## Post-Deployment Configuration

### Additional access policies (if needed)

```bash
# Grant a user or group access to specific path
globus-connect-server acl create \
  --permissions read,write \
  --principal "user@example.org" \
  --path "/s3_storage/project/"
```

### Adding mapped collections (if needed)

```bash
# Create a mapped collection for specific data subsets
globus-connect-server mapped-collection create \
  --display-name "Project Data" \
  --storage-gateway-id s3_storage \
  --root-path "/project-data/"
```

This complete deployment process gives you a fully functional Globus Connect Server with S3 connector, properly configured authentication, and initial access controls.



------

# Using Globus CLI for S3 Bucket Transfers

Here's how to use the Globus command line interface (CLI) to transfer files to and from your S3 bucket connected through Globus Connect Server:

## 1. Install Globus CLI

First, install the Globus CLI on your local machine:

```bash
# Install using pip
pip install globus-cli

# Verify installation
globus --version
```

## 2. Authenticate with Globus

```bash
# Log in to Globus
globus login

# This will open a browser window to complete authentication
# Follow the prompts to authorize the CLI
```

## 3. Find Your Endpoint IDs

```bash
# Find your Globus Connect Server endpoint
globus endpoint search "MyGlobusEndpoint"

# Note the endpoint ID, which looks like: a1b2c3d4-5678-90ef-ghij-klmnopqrstuv

# For transfer destination, find another endpoint
# For example, search for Globus tutorial endpoint
globus endpoint search "Globus Tutorial Endpoint"
```

## 4. List Files in Your S3 Bucket

```bash
# Replace ENDPOINT_ID with your endpoint ID
ENDPOINT_ID="your-endpoint-id"

# List the contents of your endpoint (showing available connectors)
globus ls "${ENDPOINT_ID}:/"

# List files in your S3 bucket through the connector
# Note: The path typically includes the connector name, e.g., "/s3_storage/"
globus ls "${ENDPOINT_ID}:/s3_storage/"
```

## 5. Transfer Files

### Option 1: One-time Transfer

```bash
# Set source and destination endpoints
SOURCE_ENDPOINT="your-endpoint-id"
DEST_ENDPOINT="destination-endpoint-id"

# Start transfer from S3 bucket to destination
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/path/to/file.txt" "${DEST_ENDPOINT}:/path/to/destination/" --label "S3 file transfer"

# Transfer multiple files
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/path/to/folder/" "${DEST_ENDPOINT}:/path/to/destination/" --recursive --label "S3 folder transfer"
```

### Option 2: Using Batch Transfer File

```bash
# Create a batch file with transfer instructions
cat > transfer.txt << EOF
/s3_storage/file1.txt /destination/file1.txt
/s3_storage/file2.txt /destination/file2.txt
/s3_storage/folder/ /destination/folder/ -r
EOF

# Execute batch transfer
globus transfer "${SOURCE_ENDPOINT}" "${DEST_ENDPOINT}" --batch transfer.txt --label "Batch S3 transfer"
```

## 6. Monitor Transfer

```bash
# List recent transfers
globus task list

# Get details of a specific transfer
globus task show TASK_ID

# Wait for transfer to complete
globus task wait TASK_ID
```

## 7. Additional Useful Commands

### Check Endpoint Details

```bash
# View detailed endpoint information
globus endpoint show ENDPOINT_ID

# Check connector details 
globus ls -l "${ENDPOINT_ID}:/" --features
```

### Verify Server-Side Configuration

```bash
# SSH into your Globus server
ssh -i your-key.pem ec2-user@<instance-public-dns>

# Check connector status
globus-connect-server storage-gateway list

# Check specific connector details
globus-connect-server storage-gateway show --connector-id s3_storage
```

### Synchronize Directories

```bash
# Sync from S3 to destination (similar to rsync)
globus transfer "${SOURCE_ENDPOINT}:/s3_storage/folder/" "${DEST_ENDPOINT}:/destination/" --sync-level=checksum --recursive --label "S3 sync"
```

## 8. Automation Example

Here's a simple script to automate a regular S3 backup to another endpoint:

```bash
#!/bin/bash
# s3_backup.sh - Scheduled S3 bucket backup via Globus

SOURCE_ENDPOINT="your-endpoint-id"
DEST_ENDPOINT="destination-endpoint-id"
LABEL="Scheduled S3 Backup $(date +%Y-%m-%d)"

# Start the transfer
TASK_ID=$(globus transfer "${SOURCE_ENDPOINT}:/s3_storage/" "${DEST_ENDPOINT}:/backups/$(date +%Y-%m-%d)/" --recursive --label "${LABEL}" --jmespath 'task_id' -F json)

echo "Transfer initiated with task ID: ${TASK_ID}"

# Optional: wait for completion
globus task wait "${TASK_ID}"
echo "Transfer complete!"
```

------

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

------

# Globus Collection Types and Relationship to S3 Connector

Globus organizes data access through "collections" (previously called "endpoints"). Here's how the various collection types relate to your S3 deployment:

## Globus Collection Types

### 1. **Server Collections**

- Created by deploying Globus Connect Server (what we're doing with the CloudFormation template)
- Enterprise-grade, high-performance collections for organizational data
- Supports multiple storage connectors (S3, POSIX, Google Drive, etc.)
- Features authentication integration, access controls, and high-performance transfers
- Requires a Globus subscription

### 2. **Personal Collections**

- Created by installing Globus Connect Personal on a laptop, desktop, or server
- Designed for individual researchers or small teams
- Limited to local file systems (cannot connect to S3 directly)
- Free tier available

### 3. **Guest Collections**

- Hosted on existing Server Collections
- Allow data owners to create virtual entry points to specific subdirectories
- Useful for sharing specific datasets with collaborators
- Different authorization policies from parent collection

### 4. **Mapped Collections**

- Virtual collections that map to specific directories in a storage system
- Allow administrators to create logical data organizations
- Control access permissions separately from physical storage

### 5. **BoxAuth Collections**

- Represent storage systems accessible through a Box-like authentication system
- Example: Google Drive connector

## How S3 Fits into Globus Collections

In your CloudFormation template, we're creating:

1. A **Server Collection** (the Globus Connect Server instance)
2. With an **S3 Storage Connector** that provides access to your S3 bucket

### The Relationship in Detail:

```
AWS Account
   └── S3 Bucket
       └── Connected via S3 Storage Connector
           └── Exposed through Globus Server Collection
               └── Accessible via Globus Transfer Service
```

### Key Points:

1. Storage vs. Collection:
   - The S3 bucket is your storage resource
   - The Globus collection is the access interface to that storage
2. Authentication Layers:
   - AWS credentials (IAM role) authenticate to S3
   - Globus credentials authenticate users to the collection
3. Performance Optimization:
   - The S3 connector is optimized for high-performance transfers
   - Uses data streaming, parallelism, and retry mechanisms
4. Sharing Capabilities:
   - You can create Guest Collections on your Server Collection
   - This allows controlled sharing of S3 data without giving direct AWS access

## Practical Applications

1. Multi-Connector Configurations:

   ```
   Your Globus Server Collection
    ├── S3 Bucket (via S3 connector)
    ├── Local Disk (via POSIX connector)
    └── Google Drive (via Google Drive connector)
   ```

2. Mapped Collections for Data Organization:

   ```
   S3 Bucket Root
    ├── Mapped as "Project A Data" (with Project A access)
    └── Mapped as "Project B Data" (with Project B access)
   ```

3. Data Transfer Management:

   - Transfer between S3 and HPC storage
   - Transfer between S3 and personal computers
   - Transfer between different S3 buckets across accounts

## Direct Transfer with Server Collections

### Server Collection Access

1. Direct Access

   :

   - Users with appropriate permissions can directly transfer files to/from a server collection
   - No intermediate guest or mapped collection is required
   - Example: `globus transfer server-endpoint-id:/path/to/file destination-endpoint-id:/path/`

2. Authentication Model

   :

   - Server collections use the authentication mechanism configured during setup
   - This can be identity providers like institutional login, Google, ORCID, etc.
   - Users authenticate directly to the server collection

3. Permission Controls

   :

   - Server collections have their own permission controls
   - Administrators define who can read/write to which paths
   - Fine-grained access control is available without creating additional collections

## When Guest/Mapped Collections Are Useful

While not required, guest and mapped collections offer specific benefits:

1. Guest Collections

   :

   - **Use case**: When you want to delegate sharing authority
   - Allow designated users to re-share specific data paths
   - Create distinct access points with their own permission sets

2. Mapped Collections

   :

   - **Use case**: Logical organization of data resources
   - Create distinct views into the same storage
   - Apply different policies to different data subsets
   - Example: Map `/project-a` and `/project-b` folders as separate collections

## Example Scenarios

### Scenario 1: Direct Server Collection Access

```
User → Authenticates to Server Collection → Transfers files to/from S3 bucket
```

- Simple, straightforward access
- Requires user to have authorization on the server collection

### Scenario 2: Using Guest Collections

```
Admin → Creates Guest Collection on S3 path → Shares with collaborator
Collaborator → Accesses Guest Collection → Transfers files to/from that specific S3 path
```

- Collaborator doesn't need access to entire server collection
- Path-limited access increases security

## With Your S3 Deployment

With the CloudFormation template we've created:

1. Users with appropriate permissions can immediately transfer files to/from the S3 bucket through the server collection.
2. You have the flexibility to set up guest or mapped collections later if your sharing needs become more complex.
3. All transfer performance benefits apply to direct server collection access - no performance penalty for skipping guest/mapped collections.

The beauty of the Globus design is this flexibility - you can start with simple direct access and evolve to more sophisticated sharing models as your needs grow.

------

#### Cloudformation template

```bash
aws cloudformation create-stack \
  --stack-name globus-gcs \
  --template-body file://globus-gcs-s3-template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    ParameterKey=AuthenticationMethod,ParameterValue=Globus \
    ParameterKey=DefaultAdminIdentity,ParameterValue=admin@yourdomain.org
```

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "CloudFormation template for Globus Connect Server with S3 Connector"

Conditions:
  HasSubscription: !Not [!Equals [!Ref GlobusSubscriptionId, ""]]
  IsProduction: !Equals [!Ref DeploymentType, "Production"]
  UseElasticIP: !Or [!Equals [!Ref DeploymentType, "Production"], !Equals [!Ref ForceElasticIP, true]]
  DeployS3Connector: !And [!Ref EnableS3Connector, HasSubscription]
  DeployPosixConnector: !And [!Ref EnablePosixConnector, HasSubscription]
  DeployGoogleDriveConnector: !And [!Ref EnableGoogleDriveConnector, HasSubscription]
  UseGlobusAuth: !Equals [!Ref AuthenticationMethod, "Globus"]
  HasDefaultAdmin: !Not [!Equals [!Ref DefaultAdminIdentity, ""]]

Parameters:
  DeploymentType:
    Description: Type of deployment (affects resource configuration)
    Type: String
    Default: Integration
    AllowedValues:
      - Integration
      - Production
    ConstraintDescription: Must be either Integration or Production.
    
  ForceElasticIP:
    Description: Force allocation of Elastic IP even for Integration deployment
    Type: Boolean
    Default: false
    
  AuthenticationMethod:
    Description: Authentication method for the Globus Connect Server
    Type: String
    Default: Globus
    AllowedValues:
      - Globus
      - MyProxy
    ConstraintDescription: Must be either Globus (for identity federation) or MyProxy (for local accounts).
    
  DefaultAdminIdentity:
    Description: Globus identity to be granted admin access (email@example.org)
    Type: String
    Default: ""

  InstanceType:
    Description: EC2 instance type for Globus Connect Server
    Type: String
    Default: m6i.xlarge
    AllowedValues:
      - m5.xlarge
      - m5.2xlarge
      - m5.4xlarge
      - m5n.xlarge
      - m5n.2xlarge
      - m5n.4xlarge
      - m6i.xlarge
      - m6i.2xlarge
      - m6i.4xlarge
      - m6in.xlarge
      - m6in.2xlarge
      - m6in.4xlarge
    ConstraintDescription: Must be a valid EC2 instance type.

  KeyName:
    Description: Name of an existing EC2 KeyPair to enable SSH access to the instance
    Type: AWS::EC2::KeyPair::KeyName
    ConstraintDescription: Must be the name of an existing EC2 KeyPair.

  AvailabilityZone:
    Description: The Availability Zone to launch the instance in
    Type: AWS::EC2::AvailabilityZone::Name

  VpcId:
    Description: VPC to deploy Globus Connect Server into
    Type: AWS::EC2::VPC::Id

  SubnetId:
    Description: Subnet within the selected VPC and Availability Zone
    Type: AWS::EC2::Subnet::Id

  S3BucketName:
    Description: Name of S3 bucket to connect to Globus
    Type: String
    AllowedPattern: "[a-zA-Z0-9\\-\\.]{3,63}"
    ConstraintDescription: Bucket name must be between 3 and 63 characters, contain only letters, numbers, hyphens, and periods.

  GlobusClientId:
    Description: Globus Client ID for registration
    Type: String
    NoEcho: true

  GlobusClientSecret:
    Description: Globus Client Secret for registration
    Type: String
    NoEcho: true

  GlobusSubscriptionId:
    Description: (Optional) Globus Subscription ID to join this endpoint to your subscription
    Type: String
    Default: ""
    
  # Connector options
  EnableS3Connector:
    Description: Enable S3 Connector (requires subscription)
    Type: Boolean
    Default: true
    
  EnablePosixConnector:
    Description: Enable POSIX Connector for local filesystem access (requires subscription)
    Type: Boolean
    Default: false
    
  EnableGoogleDriveConnector:
    Description: Enable Google Drive Connector (requires subscription)
    Type: Boolean
    Default: false

  # Connector specific parameters
  S3BucketName:
    Description: Name of S3 bucket to connect (if S3 Connector is enabled)
    Type: String
    Default: ""
    AllowedPattern: "^$|[a-zA-Z0-9\\-\\.]{3,63}"
    ConstraintDescription: Bucket name must be between 3 and 63 characters, contain only letters, numbers, hyphens, and periods.
    
  PosixPath:
    Description: Local filesystem path for POSIX Connector (if enabled)
    Type: String
    Default: "/data"

  GlobusDisplayName:
    Description: Display name for the Globus endpoint
    Type: String
    Default: "AWS-GCS-S3-Endpoint"

Mappings:
  RegionMap:
    us-east-1:
      AMI: ami-0f3c7d07486cad139 # Amazon Linux 2023 AMI in us-east-1
    us-east-2:
      AMI: ami-0cc87e5027adcdca8 # Amazon Linux 2023 AMI in us-east-2
    us-west-1:
      AMI: ami-0ce2cb35386e3b100 # Amazon Linux 2023 AMI in us-west-1
    us-west-2:
      AMI: ami-008fe2fc65df48dac # Amazon Linux 2023 AMI in us-west-2
    eu-west-1:
      AMI: ami-06d0bbd3c5e5d5055 # Amazon Linux 2023 AMI in eu-west-1
    eu-central-1:
      AMI: ami-0bc77b0b09ab632bf # Amazon Linux 2023 AMI in eu-central-1
    ap-northeast-1:
      AMI: ami-09a5c873bc79530d9 # Amazon Linux 2023 AMI in ap-northeast-1
    ap-southeast-1:
      AMI: ami-0fa377108253bf620 # Amazon Linux 2023 AMI in ap-southeast-1
    ap-southeast-2:
      AMI: ami-04f5097681773b989 # Amazon Linux 2023 AMI in ap-southeast-2

Resources:
  GlobusServerElasticIP:
    Type: AWS::EC2::EIP
    Condition: UseElasticIP
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: globus-server-eip
          
  GlobusServerSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Enable SSH and Globus Connect Server ports
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0
          Description: SSH access
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: HTTPS for Globus Connect Server
        - IpProtocol: tcp
          FromPort: 2811
          ToPort: 2811
          CidrIp: 0.0.0.0/0
          Description: GridFTP control channel
        - IpProtocol: tcp
          FromPort: 7512
          ToPort: 7512
          CidrIp: 0.0.0.0/0
          Description: Globus Connect Server authentication
        - IpProtocol: tcp
          FromPort: 50000
          ToPort: 51000
          CidrIp: 0.0.0.0/0
          Description: GridFTP data channels
      Tags:
        - Key: Name
          Value: globus-server-sg

  GlobusServerRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Path: "/"

  GlobusServerS3Policy:
    Type: AWS::IAM::Policy
    Condition: DeployS3Connector
    Properties:
      PolicyName: GlobusServerS3Access
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Action:
              - s3:ListBucket
              - s3:GetBucketLocation
            Resource: !Sub "arn:aws:s3:::${S3BucketName}"
          - Effect: Allow
            Action:
              - s3:PutObject
              - s3:GetObject
              - s3:DeleteObject
              - s3:ListMultipartUploadParts
              - s3:AbortMultipartUpload
            Resource: !Sub "arn:aws:s3:::${S3BucketName}/*"
      Roles:
        - !Ref GlobusServerRole

  GlobusServerInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Path: "/"
      Roles:
        - !Ref GlobusServerRole

  GlobusServerInstance:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: !Ref InstanceType
      KeyName: !Ref KeyName
      AvailabilityZone: !Ref AvailabilityZone
      IamInstanceProfile: !Ref GlobusServerInstanceProfile
      SecurityGroupIds:
        - !GetAtt GlobusServerSecurityGroup.GroupId
      SubnetId: !Ref SubnetId
      ImageId: !FindInMap [RegionMap, !Ref "AWS::Region", AMI]
      BlockDeviceMappings:
        - DeviceName: /dev/xvda
          Ebs:
            VolumeSize: 100
            VolumeType: gp3
            DeleteOnTermination: true
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash -xe
          exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

          # Update the system
          dnf update -y
          dnf install -y python3-pip jq curl wget gnupg2 

          # Set authentication configuration based on chosen method
          if [ "${AuthenticationMethod}" = "Globus" ]; then
            AuthenticationConfig="Authentication = Globus\nIdentityMethod = OAuth\nRequireEncryption = True"
            AuthorizationEnabled="True"
          else
            AuthenticationConfig="FetchCredentialFromRelay = True\nIdentityMethod = MyProxy"
            AuthorizationEnabled="False"
          fi

          # Install AWS CLI
          pip3 install --upgrade awscli

          # Install Globus Connect Server repository
          curl -LOs https://downloads.globus.org/globus-connect-server/stable/installers/repo/rpm/globus-repo-latest.noarch.rpm
          dnf install -y ./globus-repo-latest.noarch.rpm
          dnf install -y globus-connect-server54

          # Create Globus configuration directory
          mkdir -p /etc/globus-connect-server

          # Create Globus Connect Server configuration file
          cat > /etc/globus-connect-server/globus-connect-server.conf << 'EOF'
          [Globus]
          ClientId = ${GlobusClientId}
          ClientSecret = ${GlobusClientSecret}

          [Endpoint]
          Name = ${GlobusDisplayName}
          Public = True
          DefaultDirectory = /

          [Security]
          ${AuthenticationConfig}
          Authorization = ${AuthorizationEnabled}
          
          [GridFTP]
          Server = $(hostname -f)
          IncomingPortRange = 50000,51000
          OutgoingPortRange = 50000,51000
          RestrictPaths = 
          Sharing = True
          SharingRestrictPaths = 
          EOF

          # Configure S3 connector
          mkdir -p /opt/globus-connect-server-s3
          cat > /opt/globus-connect-server-s3/s3_connector.json << 'EOF'
          {
              "canonical_name": "s3_storage",
              "display_name": "S3 Connector",
              "storage_type": "s3",
              "connector_type": "s3",
              "authentication_method": "aws_s3_path_style",
              "configuration": {
                  "credentials_type": "role",
                  "bucket": "${S3BucketName}"
              }
          }
          EOF

          # Setup and start Globus Connect Server
          globus-connect-server-setup

          # Set up initial access policy for admin if specified
          if [ "${AuthenticationMethod}" = "Globus" ] && [ "${DefaultAdminIdentity}" != "" ]; then
            echo "Setting up initial access policy for admin: ${DefaultAdminIdentity}"
            # Wait for endpoint to be fully registered
            sleep 30
            
            # Create access policy for admin with full permissions
            globus-connect-server acl create \
              --permissions read,write \
              --principal "${DefaultAdminIdentity}" \
              --path "/"
              
            echo "Admin access policy created"
          fi

          # Configure connectors based on subscription status
          if [ "${GlobusSubscriptionId}" != "" ]; then
            echo "Configuring connectors with subscription ${GlobusSubscriptionId}..."
            
            # Configure S3 connector
            if [ "${EnableS3Connector}" = "true" ] && [ "${S3BucketName}" != "" ]; then
              echo "Setting up S3 connector for bucket ${S3BucketName}..."
              globus-connect-server storage-gateway create \
                --connector-id s3_storage \
                --connector-display-name "S3 Connector" \
                --connector-type s3 \
                --authentication-method aws_s3_path_style \
                --credentials-type role \
                --s3-bucket ${S3BucketName}
              echo "S3 connector configured"
            else
              echo "S3 connector not enabled or no bucket specified"
            fi
            
            # Configure POSIX connector
            if [ "${EnablePosixConnector}" = "true" ]; then
              echo "Setting up POSIX connector for path ${PosixPath}..."
              # Create directory if it doesn't exist
              mkdir -p ${PosixPath}
              chmod 755 ${PosixPath}
              
              globus-connect-server storage-gateway create \
                --connector-id posix_storage \
                --connector-display-name "POSIX Connector" \
                --connector-type posix \
                --root-directory ${PosixPath}
              echo "POSIX connector configured"
            else
              echo "POSIX connector not enabled"
            fi
            
            # Configure Google Drive connector
            if [ "${EnableGoogleDriveConnector}" = "true" ]; then
              echo "Setting up Google Drive connector..."
              globus-connect-server storage-gateway create \
                --connector-id googledrive_storage \
                --connector-display-name "Google Drive Connector" \
                --connector-type google_drive
              echo "Google Drive connector configured"
            else
              echo "Google Drive connector not enabled"
            fi
          else
            echo "No subscription ID provided, skipping connector setup"
          fi

          # Enable and start services
          systemctl enable globus-gridftp-server
          systemctl start globus-gridftp-server

          # Add a tag indicating installation is complete
          INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
          aws ec2 create-tags --resources $INSTANCE_ID --tags Key=GlobusInstalled,Value=true --region ${AWS::Region}
          
          # Signal CloudFormation that the instance is ready
          /opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource GlobusServerInstance --region ${AWS::Region}
          
          # Join to Globus subscription if ID is provided
          if [ "${GlobusSubscriptionId}" != "" ]; then
            # Install Globus CLI
            pip3 install globus-cli
            
            # Wait for endpoint to be fully registered
            sleep 30
            
            # Get the endpoint ID
            ENDPOINT_ID=$(globus-connect-server endpoint show | grep 'UUID' | awk '{print $2}')
            
            if [ ! -z "$ENDPOINT_ID" ]; then
              echo "Found Endpoint ID: $ENDPOINT_ID"
              
              # Create config directory and credentials file for CLI
              mkdir -p ~/.globus
              cat > ~/.globus/globus.cfg << EOF
          [cli]
          default_client_id = ${GlobusClientId}
          default_client_secret = ${GlobusClientSecret}
          EOF
              
              # Attempt to join the subscription
              echo "Joining subscription ${GlobusSubscriptionId}..."
              globus-connect-server endpoint update --subscription-id ${GlobusSubscriptionId}
              
              # Verify subscription status
              globus-connect-server endpoint show | grep subscription
            else
              echo "Could not determine endpoint ID, manual subscription joining will be required"
            fi
          else
            echo "No subscription ID provided, skipping subscription joining"
          fi
      
      Tags:
        - Key: Name
          Value: globus-connect-server
          
  GlobusServerIPAssociation:
    Type: AWS::EC2::EIPAssociation
    Condition: UseElasticIP
    Properties:
      AllocationId: !GetAtt GlobusServerElasticIP.AllocationId
      InstanceId: !Ref GlobusServerInstance

Outputs:
  InstanceId:
    Description: Instance ID of the Globus Connect Server
    Value: !Ref GlobusServerInstance

  PrivateIP:
    Description: Private IP address of the Globus Connect Server
    Value: !GetAtt GlobusServerInstance.PrivateIp

  ElasticIP:
    Description: Elastic IP address assigned to the Globus Connect Server
    Condition: UseElasticIP
    Value: !Ref GlobusServerElasticIP
    
  PublicDNS:
    Description: Public DNS name of the Globus Connect Server
    Value: !GetAtt GlobusServerInstance.PublicDnsName

  GlobusEndpointURL:
    Description: URL to access the Globus Endpoint
    Value: !Sub "https://app.globus.org/file-manager?origin_id=${GlobusDisplayName}"
    
  SubscriptionStatus:
    Description: Globus Subscription Status
    Value: !If [HasSubscription, "Endpoint joined to subscription", "No subscription ID provided"]
    
  PublicAddress:
    Description: Public address to use for Globus redirect URI configuration
    Value: !If 
      - UseElasticIP
      - !Sub "https://${GlobusServerElasticIP}"
      - !Sub "https://${GlobusServerInstance.PublicIp}"

  S3BucketConnected:
    Description: S3 Bucket connected to Globus
    Condition: DeployS3Connector
    Value: !Ref S3BucketName
    
  ConnectorsEnabled:
    Description: Connectors that were enabled for this deployment
    Value: !Join 
      - ", "
      - !If 
        - HasSubscription
        - !Split
          - "|"
          - !Join
            - "|"
            - - !If [DeployS3Connector, "S3", ""]
              - !If [DeployPosixConnector, "POSIX", ""]  
              - !If [DeployGoogleDriveConnector, "Google Drive", ""]
        - ["No connectors (subscription required)"]
    
  DeploymentConfiguration:
    Description: Deployment configuration information
    Value: !If 
      - UseElasticIP
      - !If [IsProduction, "Production deployment with Elastic IP", "Integration deployment with Elastic IP (forced)"]
      - "Integration deployment with dynamic public IP"
      
  AuthenticationConfiguration:
    Description: Authentication method configured for Globus
    Value: !If 
      - UseGlobusAuth
      - "Globus Auth (identity federation)"
      - "MyProxy (local accounts required)"
      
  InitialAccessInfo:
    Description: Initial access configuration
    Value: !If
      - UseGlobusAuth
      - !If 
        - HasDefaultAdmin
        - !Sub "Admin access granted to ${DefaultAdminIdentity}"
        - "No default admin configured - access policies must be set manually"
      - "Using MyProxy authentication - local accounts required"
```

