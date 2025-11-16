# AWS Account Setup Guide for V2VBot

This guide helps you set up a brand new AWS account for V2VBot deployment.

## Prerequisites

- Brand new AWS account with root user: b28313248@gmail.com
- Billing enabled on the account
- Access to root user email for verification

## Step-by-Step Setup

### Step 1: Log in to AWS Console

1. Go to: https://console.aws.amazon.com/
2. Sign in with root user: **b28313248@gmail.com**
3. Enter password when prompted
4. Complete any security verification if required

### Step 2: Create IAM User (Recommended)

**Why IAM User?**
- More secure than using root credentials
- Can limit permissions
- Best practice for programmatic access

**Steps:**

1. Go to **IAM Console**: https://console.aws.amazon.com/iam/
2. Click **Users** → **Create user**
3. **User name**: `v2vbot-user`
4. **Access type**: Check **"Provide user access to the AWS Management Console"** (optional) and **"Programmatic access"** (required)
5. Click **Next**

**Set Permissions:**
- Select **"Attach policies directly"**
- Search and select:
  - `AmazonEC2FullAccess` (for EC2 instances)
  - `AmazonVPCFullAccess` (for networking)
  - `IAMReadOnlyAccess` (optional, for reading IAM info)
6. Click **Next** → **Next** → **Create user**

**Save Credentials:**
- **Access Key ID**: Copy and save this
- **Secret Access Key**: Copy and save this (shown only once!)
- Click **Done**

### Step 3: Configure AWS CLI

**Option A: Using the Setup Script (Easiest)**

```bash
./aws/aws_account_setup.sh
```

This will:
- Check/install AWS CLI
- Prompt you to run `aws configure`
- Create EC2 key pair
- Verify setup

**Option B: Manual Configuration**

```bash
aws configure
```

Enter:
- **AWS Access Key ID**: [From Step 2]
- **AWS Secret Access Key**: [From Step 2]
- **Default region**: `ap-south-2` (Hyderabad, India)
- **Default output format**: `json`

### Step 4: Verify Setup

```bash
# Check authentication
aws sts get-caller-identity

# Check EC2 access
aws ec2 describe-regions --region-names ap-south-2
```

### Step 5: Create EC2 Key Pair

The setup script will create this automatically, or create manually:

```bash
aws ec2 create-key-pair \
    --region ap-south-2 \
    --key-name v2vbot-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/v2vbot-key.pem

chmod 400 ~/.ssh/v2vbot-key.pem
```

### Step 6: Enable EC2 Service (If Needed)

For brand new accounts, EC2 might need activation:

1. Go to: https://console.aws.amazon.com/ec2/v2/home
2. If prompted, click **"Get started with Amazon EC2"**
3. This activates the EC2 service

### Step 7: Request Service Quotas (If Needed)

For GPU instances, you may need to request quota increases:

1. Go to: https://console.aws.amazon.com/servicequotas/
2. Search for: **"Running On-Demand G instances"**
3. Request quota increase if needed (usually starts at 0)

## Quick Setup Script

Run the automated setup:

```bash
./aws/aws_account_setup.sh
```

This script will:
1. ✅ Check AWS CLI installation
2. ✅ Guide you through `aws configure`
3. ✅ Verify authentication
4. ✅ Create EC2 key pair
5. ✅ Set default region

## Troubleshooting

### "Access Denied" Errors

**Solution:**
- Ensure IAM user has `AmazonEC2FullAccess` policy
- Check if using correct access keys
- Verify region is correct

### "Service Not Available" Errors

**Solution:**
- Go to EC2 Console and activate service
- Some services need manual activation for new accounts

### "Quota Exceeded" Errors

**Solution:**
- Request quota increase: https://console.aws.amazon.com/servicequotas/
- Search for "Running On-Demand G instances"
- Request increase to at least 1

### Key Pair Issues

**Solution:**
- Key pairs are region-specific
- Create key pair in the same region where you'll create instances
- Save private key securely (shown only once)

## Security Best Practices

1. **Don't use root credentials** - Always use IAM users
2. **Enable MFA** - Add multi-factor authentication to root account
3. **Use least privilege** - Only grant necessary permissions
4. **Rotate keys regularly** - Change access keys periodically
5. **Monitor usage** - Set up billing alerts

## Next Steps

After setup is complete:

1. **Create EC2 Instance:**
   ```bash
   ./aws/aws_create_instance.sh
   ```

2. **Check Status:**
   ```bash
   ./aws/aws_get_status.sh
   ```

3. **Start/Stop as Needed:**
   ```bash
   ./aws/aws_start_instance.sh
   ./aws/aws_stop_instance.sh
   ```

## Useful Links

- **AWS Console**: https://console.aws.amazon.com/
- **EC2 Console**: https://console.aws.amazon.com/ec2/v2/home
- **IAM Console**: https://console.aws.amazon.com/iam/
- **Billing Dashboard**: https://console.aws.amazon.com/billing/
- **Service Quotas**: https://console.aws.amazon.com/servicequotas/

