#!/bin/bash
# Create AMI (Amazon Machine Image) from EC2 instance to preserve all data
# This allows you to save your work before terminating a one-time spot instance

set -e

INSTANCE_NAME="v2vbot-vm"
AMI_NAME_PREFIX="v2vbot-backup"

# All regions that create_instance tries
REGIONS=("ap-south-1" "ap-south-2" "eu-west-1" "us-east-1" "ap-southeast-1")

echo "📸 Creating AMI from EC2 instance to preserve all data..."
echo "   This will create a snapshot of your entire instance (disk + configuration)"
echo ""

# Find instance in all regions
INSTANCE_FOUND=false
FOUND_REGION=""
FOUND_INSTANCE_ID=""

for region in "${REGIONS[@]}"; do
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_INFO" ] && [ "$INSTANCE_INFO" != "None" ]; then
        INSTANCE_ID=$(echo "$INSTANCE_INFO" | awk '{print $1}' | head -1)
        STATE=$(echo "$INSTANCE_INFO" | awk '{print $2}' | head -1)
        
        if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
            INSTANCE_FOUND=true
            FOUND_REGION="$region"
            FOUND_INSTANCE_ID="$INSTANCE_ID"
            break
        fi
    fi
done

if [ "$INSTANCE_FOUND" = false ]; then
    echo "❌ Instance '$INSTANCE_NAME' not found in any region"
    echo ""
    echo "   Regions checked:"
    for region in "${REGIONS[@]}"; do
        echo "     - $region"
    done
    exit 1
fi

REGION="$FOUND_REGION"
INSTANCE_ID="$FOUND_INSTANCE_ID"

# Get instance details
INSTANCE_TYPE=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].InstanceType' \
    --output text 2>/dev/null || echo "unknown")

STATE=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

echo "📝 Found instance:"
echo "   Instance ID: $INSTANCE_ID"
echo "   Region: $REGION"
echo "   Instance Type: $INSTANCE_TYPE"
echo "   State: $STATE"
echo ""

# Check if instance is running (recommended for AMI creation)
if [ "$STATE" != "running" ] && [ "$STATE" != "stopped" ]; then
    echo "⚠️  Instance is in '$STATE' state"
    echo "   AMI creation works best when instance is running or stopped"
    echo "   Waiting for instance to be in a stable state..."
    read -p "   Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        exit 0
    fi
fi

# Generate AMI name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AMI_NAME="${AMI_NAME_PREFIX}-${TIMESTAMP}"
AMI_DESCRIPTION="Backup of $INSTANCE_NAME ($INSTANCE_ID) created on $(date)"

echo "📸 Creating AMI..."
echo "   AMI Name: $AMI_NAME"
echo "   Description: $AMI_DESCRIPTION"
echo ""
echo "   ⏳ This may take 5-15 minutes depending on disk size..."
echo "   (The instance will continue running during this process)"
echo ""

# Create AMI
AMI_RESULT=$(aws ec2 create-image \
    --region $REGION \
    --instance-id $INSTANCE_ID \
    --name "$AMI_NAME" \
    --description "$AMI_DESCRIPTION" \
    --no-reboot \
    --output text 2>&1)

if echo "$AMI_RESULT" | grep -q "ami-"; then
    AMI_ID=$(echo "$AMI_RESULT" | grep -o "ami-[a-z0-9]*" | head -1)
    
    echo "✅ AMI creation started successfully!"
    echo ""
    echo "📝 AMI Details:"
    echo "   AMI ID: $AMI_ID"
    echo "   AMI Name: $AMI_NAME"
    echo "   Region: $REGION"
    echo ""
    echo "🔗 View in AWS Console:"
    echo "   https://console.aws.amazon.com/ec2/v2/home?region=$REGION#Images:visibility=owned-by-me;imageId=$AMI_ID"
    echo ""
    echo "⏳ AMI Status:"
    echo "   The AMI is being created in the background."
    echo "   You can check status with:"
    echo "   aws ec2 describe-images --region $REGION --image-ids $AMI_ID --query 'Images[0].State' --output text"
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Wait for AMI to be 'available' (check status above)"
    echo "   2. Once available, you can safely terminate the current instance"
    echo "   3. Create a new instance from this AMI using:"
    echo "      ./aws/aws_create_instance_from_ami.sh $AMI_ID"
    echo ""
    echo "💰 Cost Note:"
    echo "   - AMI storage: ~₹0.20-0.50/month per GB (similar to EBS snapshot)"
    echo "   - 30GB AMI ≈ ~₹6-15/month"
    echo "   - You can delete old AMIs to save costs"
    echo ""
    
    # Wait a moment and check initial status
    sleep 3
    AMI_STATE=$(aws ec2 describe-images \
        --region $REGION \
        --image-ids $AMI_ID \
        --query 'Images[0].State' \
        --output text 2>/dev/null || echo "unknown")
    
    echo "   Current AMI State: $AMI_STATE"
    echo ""
    
    # Save AMI ID to a file for reference
    AMI_INFO_FILE="$HOME/.v2vbot-ami-info.txt"
    echo "$AMI_ID|$AMI_NAME|$REGION|$(date)" >> "$AMI_INFO_FILE"
    echo "   💾 AMI info saved to: $AMI_INFO_FILE"
    echo ""
    
else
    ERROR=$(echo "$AMI_RESULT" | grep -i "error\|denied\|unauthorized" || echo "$AMI_RESULT")
    echo "❌ Failed to create AMI:"
    echo "   $ERROR"
    echo ""
    echo "💡 Troubleshooting:"
    echo "   1. Check AWS permissions (IAM policy needs ec2:CreateImage)"
    echo "   2. Ensure instance is in a valid state (running or stopped)"
    echo "   3. Check if you have sufficient quota for AMIs"
    exit 1
fi

