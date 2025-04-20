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
       └── Connected via S3 Storage Connector (with domain restrictions)
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
3. Domain Restrictions:
   - S3 paths are restricted based on the configured domain pattern
   - The `GlobusS3Domain` parameter (e.g., "s3://*") defines allowed paths
   - Provides an additional layer of security and access control
4. Performance Optimization:
   - The S3 connector is optimized for high-performance transfers
   - Uses data streaming, parallelism, and retry mechanisms
5. Sharing Capabilities:
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

1. Direct Access:

   - Users with appropriate permissions can directly transfer files to/from a server collection
   - No intermediate guest or mapped collection is required
   - Example: `globus transfer server-endpoint-id:/path/to/file destination-endpoint-id:/path/`

2. Authentication Model:

   - Server collections use the authentication mechanism configured during setup
   - This can be identity providers like institutional login, Google, ORCID, etc.
   - Users authenticate directly to the server collection

3. Permission Controls:

   - Server collections have their own permission controls
   - Administrators define who can read/write to which paths
   - Fine-grained access control is available without creating additional collections

## When Guest/Mapped Collections Are Useful

While not required, guest and mapped collections offer specific benefits:

1. Guest Collections:

   - **Use case**: When you want to delegate sharing authority
   - Allow designated users to re-share specific data paths
   - Create distinct access points with their own permission sets

2. Mapped Collections:

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