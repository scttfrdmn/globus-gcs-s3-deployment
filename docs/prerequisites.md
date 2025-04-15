# Globus Connect Server Deployment Prerequisites

Before deploying the CloudFormation template for Globus Connect Server with S3 connector, several setup steps must be completed in the Globus web interface to create and configure the required service account and permissions.

## 1. Create a Globus Project

1. Navigate to [Globus Developer Settings](https://app.globus.org/settings/developers)
2. Click "Add Project"
3. Enter a Name for your project and a Contact Email
4. Save the **Project ID** - you'll need this for the CloudFormation template

## 2. Create a Service Account

1. In your new project, click "Add..." and select "Add App"
2. Select "Service Account Registration"
3. Enter/Select the project name you just created and provide an App Name (e.g., "CFN Service Account")
4. This will generate:
   - A **Client ID** (save this for the CloudFormation template)
   - The **Service Account Identity** (save this as the GlobusOwner parameter)
5. Create a **Client Secret** and save it (you'll need this for the CloudFormation template)

## 3. Make the Service Account a Project Admin

1. Navigate to [Globus Auth Developers](https://auth.globus.org/v2/web/developers)
2. Find and select your project
3. Click "Add" and select "Add/remove admins"
4. Enter the Service Account Identity you created in step 2
5. Click "Add as admin"

## 4. Grant Subscription Group Access (for S3 Connector)

> **IMPORTANT**: This step requires existing administrator privileges in your Globus subscription group. If you don't have these privileges, you'll need to contact a subscription administrator.

The S3 connector is a premium feature that requires both a Globus subscription and specific permissions for your service account:

1. Navigate to [Globus Groups](https://app.globus.org/groups)
2. Find and select your subscription group (not the subscription admin group)
3. Click "View members" 
4. Click "Invite Others"
5. Enter the Service Account Identity and click "Send Invitation"
6. Return to the group members view where you should now see the service account
7. Click on the service account identity, then click the pencil icon next to the role
8. Change the role to "Administrator" and save

> **NOTE**: Without this step, the S3 connector portion of the deployment will fail. If you don't have permissions to perform this step, you may need to contact your Globus administrators who may already have a properly configured service account you can use.

## 5. Collect Required Parameters

Before running the CloudFormation template, make sure you have collected:

- **Project ID** - From step 1
- **Client ID** - From step 2
- **Client Secret** - From step 2
- **Service Account Identity** - From step 2 (to use as GlobusOwner)
- **Subscription ID** - If using the S3 connector (obtain from your Globus administrator)
- **S3 Bucket Name** - An existing S3 bucket in your AWS account

## Deployment

After completing these prerequisites, you can proceed with the CloudFormation deployment using the collected parameters.