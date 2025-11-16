# AWS EC2 Login Methods

## Question: Can I use just AWS CLI to login?

**Short Answer:** Yes, but with some setup. There are multiple ways to connect to EC2 instances.

## Method 1: Traditional SSH (Most Common)

**Requires:** Key pair file (`.pem` file)

```bash
# Get public IP first
PUBLIC_IP=$(aws ec2 describe-instances \
    --region ap-south-2 \
    --filters "Name=tag:Name,Values=v2vbot-vm" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# SSH into instance
ssh -i ~/.ssh/v2vbot-key.pem ubuntu@$PUBLIC_IP
```

**Pros:**
- ✅ Standard method
- ✅ Works immediately
- ✅ No additional setup needed

**Cons:**
- ❌ Requires key pair file
- ❌ Requires public IP
- ❌ Security group must allow SSH (port 22)

## Method 2: AWS Systems Manager Session Manager (No SSH Keys!)

**Requires:** SSM Agent on instance + IAM role

**Setup (One-time):**

1. **Attach IAM role to instance** with `AmazonSSMManagedInstanceCore` policy
2. **SSM Agent** is pre-installed on Amazon Linux and Ubuntu AMIs

**Connect:**
```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --region ap-south-2 \
    --filters "Name=tag:Name,Values=v2vbot-vm" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

# Connect via Session Manager (no SSH keys needed!)
aws ssm start-session --region ap-south-2 --target $INSTANCE_ID
```

**Pros:**
- ✅ No SSH keys needed
- ✅ No public IP needed
- ✅ More secure (no open SSH port)
- ✅ Works through AWS CLI

**Cons:**
- ❌ Requires IAM role setup
- ❌ Slightly more complex initial setup

## Method 3: AWS Console Browser-Based SSH

1. Go to EC2 Console
2. Select your instance
3. Click **"Connect"** button
4. Choose **"EC2 Instance Connect"** or **"Session Manager"**
5. Click **"Connect"** - opens browser-based terminal

**Pros:**
- ✅ No SSH keys needed
- ✅ Works from browser
- ✅ Easy to use

**Cons:**
- ❌ Requires browser access
- ❌ May need IAM role for Session Manager

## Recommended: Update Script to Support SSM

I can update the create instance script to:
1. Create IAM role with SSM permissions
2. Attach role to instance
3. Enable Session Manager access

Then you can connect with just:
```bash
aws ssm start-session --target <instance-id>
```

**Would you like me to update the script to support Session Manager?**

## Quick Comparison

| Method | Requires Keys? | Requires Public IP? | Setup Complexity |
|--------|---------------|-------------------|------------------|
| **SSH** | ✅ Yes | ✅ Yes | ⭐ Easy |
| **Session Manager** | ❌ No | ❌ No | ⭐⭐ Medium |
| **Browser SSH** | ❌ No | ❌ No | ⭐ Easy |

## Current Setup

Right now, the scripts use **traditional SSH** because:
- ✅ Works immediately
- ✅ No additional IAM setup needed
- ✅ Standard method

But I can add Session Manager support if you prefer!


