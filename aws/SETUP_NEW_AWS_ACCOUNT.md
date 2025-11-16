# Complete AWS Account Setup - Step by Step

This guide walks you through setting up your brand new AWS account (b28313248@gmail.com) for V2VBot.

## Part 1: AWS Console Setup (Web Interface)

### Step 1: Log in to AWS Console

1. Go to: https://console.aws.amazon.com/
2. Click **"Sign in to the console"**
3. Enter root user email: **b28313248@gmail.com**
4. Enter password (you'll be prompted)
5. Complete any security verification if required

### Step 2: Enable Billing Alerts (Important!)

1. Go to: https://console.aws.amazon.com/billing/
2. Click **"Billing preferences"**
3. Enable **"Receive Billing Alerts"**
4. Set up CloudWatch billing alarm (optional but recommended)

### Step 3: Create IAM User for Programmatic Access

**Why?** Using root credentials for CLI is not secure. Create an IAM user instead.

1. Go to **IAM Console**: https://console.aws.amazon.com/iam/
2. Click **Users** in left sidebar
3. Click **"Create user"** button
4. **User name**: Enter `v2vbot-user`
5. Click **"Next"**

**Set Permissions:**
1. Select **"Attach policies directly"**
2. Search for and check these policies:
   - ✅ `AmazonEC2FullAccess` - For creating/managing EC2 instances
   - ✅ `AmazonVPCFullAccess` - For networking (security groups, etc.)
3. Click **"Next"** → **"Next"**
4. Click **"Create user"**

**IMPORTANT: Save Access Keys**
1. After user is created, click on the user name `v2vbot-user`
2. Go to **"Security credentials"** tab
3. Scroll to **"Access keys"** section
4. Click **"Create access key"**
5. Select **"Command Line Interface (CLI)"**
6. Check the confirmation box
7. Click **"Next"** → **"Create access key"**
8. **COPY AND SAVE:**
   - **Access Key ID**: `AKIA...` (save this!)
   - **Secret Access Key**: `xxxxx...` (save this! You won't see it again!)
9. Click **"Done"**

### Step 4: Activate EC2 Service

1. Go to: https://console.aws.amazon.com/ec2/v2/home
2. If you see "Get started with Amazon EC2", click it
3. This activates the EC2 service for your account

### Step 5: Import EC2 Key Pair to All Regions (One-Time)

**Important:** If you already have a key pair (`~/.ssh/v2vbot-key.pem`), import it to all regions:

```bash
./aws/aws_account_setup.sh
```

This will:
- Use your existing key pair from `~/.ssh/v2vbot-key.pem`
- Import it to all AWS regions automatically
- Allow you to use the same key across all regions

**If you don't have a key pair yet:**
```bash
# Create key pair in one region
aws ec2 create-key-pair --region ap-south-2 --key-name v2vbot-key --query 'KeyMaterial' --output text > ~/.ssh/v2vbot-key.pem
chmod 400 ~/.ssh/v2vbot-key.pem

# Then import to all regions
./aws/aws_account_setup.sh
```

**Note:** This is a one-time setup. The key pair will be reused for all future instances.

### Step 6: Request GPU Instance Quota (If Needed)

1. Go to: https://console.aws.amazon.com/servicequotas/
2. Select region: **Asia Pacific (Hyderabad) ap-south-2**
3. Search for: **"Running On-Demand G instances"**
4. Click on it
5. If quota is 0, click **"Request quota increase"**
6. Request at least **1** GPU instance
7. Submit request (usually approved quickly for new accounts)

## Part 2: Configure AWS CLI (Command Line)

### Step 6: Configure AWS CLI

Open terminal and run:

```bash
aws configure
```

Enter the following when prompted:

1. **AWS Access Key ID**: [Paste the Access Key ID from Step 3]
2. **AWS Secret Access Key**: [Paste the Secret Access Key from Step 3]
3. **Default region name**: `ap-south-2` (Hyderabad, India)
4. **Default output format**: `json`

### Step 7: Verify Configuration

```bash
# Check authentication
aws sts get-caller-identity

# Should show your account ID and user ARN
```

### Step 8: Import Key Pair to All Regions (One-Time)

**Important:** If you already have a key pair, import it to all regions:

```bash
./aws/aws_account_setup.sh
```

This imports your existing key pair (`~/.ssh/v2vbot-key.pem`) to all AWS regions. You only need to run this once!

### Step 9: Run Account Setup Script (Optional)

```bash
cd /Users/balajiv/Documents/coderepos/V2VBot
./aws/aws_account_setup.sh
```

This will:
- Verify AWS CLI is configured
- Create EC2 key pair automatically
- Set default region
- Verify everything is working

## Part 3: Create EC2 Instance

### Step 10: Create GPU Instance

Once setup is complete:

```bash
./aws/aws_create_instance.sh
```

This script will:
- Try multiple regions (India, Europe, US, Singapore)
- Try multiple GPU types (T4, A10G, V100)
- Try on-demand first, then spot instances
- Automatically create security groups
- Set up everything needed

## Quick Reference

**Account Details:**
- Root Email: b28313248@gmail.com
- IAM User: v2vbot-user
- Default Region: ap-south-2 (Hyderabad, India)

**Important Links:**
- AWS Console: https://console.aws.amazon.com/
- EC2 Console: https://console.aws.amazon.com/ec2/v2/home
- IAM Console: https://console.aws.amazon.com/iam/
- Billing: https://console.aws.amazon.com/billing/
- Service Quotas: https://console.aws.amazon.com/servicequotas/

**After Setup:**
- Create instance: `./aws/aws_create_instance.sh`
- Check status: `./aws/aws_get_status.sh`
- Start instance: `./aws/aws_start_instance.sh`
- Stop instance: `./aws/aws_stop_instance.sh`

## Troubleshooting

### "Access Denied" when running AWS CLI

**Solution:**
- Verify IAM user has `AmazonEC2FullAccess` policy
- Check if access keys are correct
- Ensure you're using the new account's credentials

### "Service Not Available"

**Solution:**
- Go to EC2 Console and activate the service
- Some services need manual activation for new accounts

### "Quota Exceeded"

**Solution:**
- Request quota increase in Service Quotas console
- Search for "Running On-Demand G instances"
- Request at least 1

---

**Ready to start?** Follow the steps above, then run `./aws/aws_account_setup.sh` to complete the setup!

