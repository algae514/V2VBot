# AWS Console Guide - Viewing Instance Creation Requests

When you run `./aws/aws_create_instance.sh`, you can verify the request in the AWS Console immediately.

## Where to See Your Instance Request

### Method 1: EC2 Instances Dashboard (Easiest)

1. **Go to EC2 Console:**
   - Direct link: https://console.aws.amazon.com/ec2/v2/home
   - Or navigate: AWS Console → Services → EC2 → Instances

2. **Select the correct region:**
   - The script tries these regions in order:
     - `ap-south-1` (Mumbai, India)
     - `ap-south-2` (Hyderabad, India)
     - `eu-west-1` (Ireland, Europe)
     - `us-east-1` (N. Virginia, US)
     - `ap-southeast-1` (Singapore)
   - Use the region selector in the top-right corner

3. **Look for your instance:**
   - Name: `v2vbot-vm`
   - State: `pending` (being created) → `running` (ready)
   - Instance ID: `i-xxxxxxxxxxxxx`

4. **What you'll see:**
   - **Pending**: Instance is being created (1-2 minutes)
   - **Running**: Instance is ready to use
   - **Stopped**: Instance was stopped (saves costs)

### Method 2: Direct Link (After Creation)

The script outputs a direct console link after successful creation:
```
🔗 View in AWS Console:
   https://console.aws.amazon.com/ec2/v2/home?region=ap-south-1#Instances:instanceId=i-xxxxxxxxxxxxx
```

Click this link to go directly to your instance.

### Method 3: CloudTrail (API Call History)

To see the exact API call that created the instance:

1. **Go to CloudTrail:**
   - https://console.aws.amazon.com/cloudtrail/home
   - Or: AWS Console → Services → CloudTrail

2. **View Event History:**
   - Click "Event history" in left sidebar
   - Filter by:
     - **Event name**: `RunInstances`
     - **Time range**: Last 1 hour
     - **Resource name**: `v2vbot-vm` (if tagged)

3. **What you'll see:**
   - API call: `RunInstances`
   - User: Your IAM user
   - Region: Where instance was created
   - Status: `Success` or `Failed`
   - Request parameters: Instance type, AMI, etc.

## Instance States Explained

| State | Meaning | What to Do |
|-------|---------|------------|
| **pending** | Instance is being created | Wait 1-2 minutes |
| **running** | Instance is ready | You can SSH in |
| **stopping** | Instance is shutting down | Wait for it to stop |
| **stopped** | Instance is stopped (saves costs) | Use `./aws/aws_start_instance.sh` to start |
| **terminated** | Instance is deleted | Cannot use anymore |

## Quick Check Commands

### Check if instance exists (all regions):
```bash
./aws/aws_get_status.sh
```

### Check specific region:
```bash
aws ec2 describe-instances \
    --region ap-south-1 \
    --filters "Name=tag:Name,Values=v2vbot-vm" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' \
    --output table
```

### Check all regions at once:
```bash
for region in ap-south-1 ap-south-2 eu-west-1 us-east-1 ap-southeast-1; do
    echo "=== $region ==="
    aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=v2vbot-vm" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
        --output table
done
```

## Troubleshooting

### "I don't see my instance in the console"

1. **Check the correct region:**
   - The script tries multiple regions
   - Check all 5 regions listed above
   - Use the region selector in EC2 console

2. **Check if creation failed:**
   - Look at the script output for error messages
   - Check CloudTrail for failed API calls
   - Common issues:
     - Account verification pending
     - Quota exceeded
     - Instance type not available

3. **Check instance name:**
   - Filter by name: `v2vbot-vm`
   - Or filter by instance ID (shown in script output)

### "Instance shows as 'pending' for a long time"

- Normal: 1-2 minutes for GPU instances
- If > 5 minutes: Check status checks in console
- If > 10 minutes: May be stuck, try stopping/starting

### "I see multiple instances"

- The script checks for existing instances before creating
- If you see duplicates, delete them:
  ```bash
  ./aws/aws_delete_instance.sh
  ```
- This will find and delete ALL instances with name `v2vbot-vm`

## Console Links by Region

Quick links to EC2 console for each region:

- **Mumbai (ap-south-1)**: https://console.aws.amazon.com/ec2/v2/home?region=ap-south-1#Instances:
- **Hyderabad (ap-south-2)**: https://console.aws.amazon.com/ec2/v2/home?region=ap-south-2#Instances:
- **Ireland (eu-west-1)**: https://console.aws.amazon.com/ec2/v2/home?region=eu-west-1#Instances:
- **N. Virginia (us-east-1)**: https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:
- **Singapore (ap-southeast-1)**: https://console.aws.amazon.com/ec2/v2/home?region=ap-southeast-1#Instances:

## Real-Time Monitoring

### Watch instance status in real-time:
```bash
watch -n 5 './aws/aws_get_status.sh'
```

This refreshes every 5 seconds to show current status.

### Monitor in console:
1. Go to EC2 → Instances
2. Select your instance
3. Click "Status checks" tab
4. Watch for:
   - System status: `passed` (green)
   - Instance status: `passed` (green)

## Cost Monitoring

### View current charges:
1. Go to: https://console.aws.amazon.com/billing/home
2. Click "Bills" to see current month charges
3. Filter by service: EC2

### Set up billing alerts:
1. Go to: https://console.aws.amazon.com/billing/home#/preferences
2. Enable "Receive Billing Alerts"
3. Set up CloudWatch billing alarm

---

**Pro Tip**: Bookmark the EC2 console link for your primary region for quick access!






