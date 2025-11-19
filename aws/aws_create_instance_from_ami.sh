#!/bin/bash
# Create EC2 instance from an existing AMI
# Use this after creating an AMI to restore your saved instance

set -e

# Default AMI ID (your saved backup)
DEFAULT_AMI_ID="ami-068fbb4aeefb15ebc"
DEFAULT_REGION="ap-south-1"

if [ $# -eq 0 ]; then
    # No arguments - use defaults
    AMI_ID="$DEFAULT_AMI_ID"
    REGION="$DEFAULT_REGION"
    PRICING="spot"
elif [ $# -eq 1 ]; then
    # One argument - could be AMI_ID or REGION
    if [[ "$1" =~ ^ami- ]]; then
        # It's an AMI ID
        AMI_ID="$1"
        REGION="$DEFAULT_REGION"
        PRICING="spot"
    else
        # Assume it's a region, use default AMI
        AMI_ID="$DEFAULT_AMI_ID"
        REGION="$1"
        PRICING="spot"
    fi
elif [ $# -eq 2 ]; then
    # Two arguments - AMI_ID and REGION, or REGION and PRICING
    if [[ "$1" =~ ^ami- ]]; then
        # First is AMI ID
        AMI_ID="$1"
        REGION="$2"
        PRICING="spot"
    else
        # First is region, second is pricing
        AMI_ID="$DEFAULT_AMI_ID"
        REGION="$1"
        PRICING="$2"
    fi
else
    # Three arguments - AMI_ID, REGION, PRICING
    AMI_ID="$1"
    REGION="$2"
    PRICING="$3"
fi

# Validate pricing option
if [ "$PRICING" != "spot" ] && [ "$PRICING" != "on-demand" ]; then
    echo "Usage: $0 [AMI_ID] [REGION] [PRICING]"
    echo ""
    echo "Arguments (all optional):"
    echo "  AMI_ID   - The AMI ID to create instance from (default: $DEFAULT_AMI_ID)"
    echo "  REGION   - AWS region (default: $DEFAULT_REGION)"
    echo "  PRICING  - 'spot' or 'on-demand' (default: spot)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use all defaults"
    echo "  $0 ap-south-1                         # Use default AMI, custom region"
    echo "  $0 ap-south-1 spot                    # Use default AMI, custom region and pricing"
    echo "  $0 ami-0123456789abcdef0              # Custom AMI, default region"
    echo "  $0 ami-0123456789abcdef0 ap-south-1   # Custom AMI and region"
    echo "  $0 ami-0123456789abcdef0 ap-south-1 on-demand  # All custom"
    echo ""
    echo "To find your AMI ID, run:"
    echo "  aws ec2 describe-images --region $DEFAULT_REGION --owners self --query 'Images[*].[ImageId,Name,CreationDate]' --output table"
    exit 1
fi

INSTANCE_NAME="v2vbot-vm"
KEY_NAME="v2vbot-key"
SECURITY_GROUP="v2vbot-sg"

echo "🚀 Creating EC2 instance from AMI..."
echo "   AMI ID: $AMI_ID"
echo "   Region: $REGION"
echo ""

# Check AWS authentication
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS not authenticated. Run ./aws/aws_setup.sh first"
    exit 1
fi

# Verify AMI exists
AMI_INFO=$(aws ec2 describe-images \
    --region $REGION \
    --image-ids $AMI_ID \
    --query 'Images[0].[ImageId,Name,State]' \
    --output text 2>/dev/null || echo "")

if [ -z "$AMI_INFO" ] || [ "$AMI_INFO" = "None" ]; then
    echo "❌ AMI '$AMI_ID' not found in region '$REGION'"
    echo ""
    echo "   Check if:"
    echo "   1. AMI ID is correct"
    echo "   2. Region is correct (AMI is region-specific)"
    echo "   3. AMI exists and is available"
    echo ""
    echo "   List your AMIs:"
    echo "   aws ec2 describe-images --region $REGION --owners self --query 'Images[*].[ImageId,Name,CreationDate]' --output table"
    exit 1
fi

AMI_NAME=$(echo "$AMI_INFO" | awk '{print $2}')
AMI_STATE=$(echo "$AMI_INFO" | awk '{print $3}')

if [ "$AMI_STATE" != "available" ]; then
    echo "❌ AMI is not available (current state: $AMI_STATE)"
    echo "   Wait for AMI to be 'available' before creating instance"
    exit 1
fi

echo "✓ AMI found: $AMI_NAME (State: $AMI_STATE)"
echo ""

# Get instance type from AMI tags or use default
INSTANCE_TYPE=$(aws ec2 describe-images \
    --region $REGION \
    --image-ids $AMI_ID \
    --query 'Images[0].Tags[?Key==`InstanceType`].Value' \
    --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_TYPE" ] || [ "$INSTANCE_TYPE" = "None" ]; then
    # Try to get instance type from AMI name or use default
    if echo "$AMI_NAME" | grep -q "g4dn"; then
        INSTANCE_TYPE="g4dn.xlarge"
    elif echo "$AMI_NAME" | grep -q "g5"; then
        INSTANCE_TYPE="g5.xlarge"
    else
        INSTANCE_TYPE="g4dn.xlarge"  # Default
    fi
fi

# Validate pricing option
if [ "$PRICING" != "spot" ] && [ "$PRICING" != "on-demand" ]; then
    echo "❌ Invalid pricing option: $PRICING"
    echo "   Must be 'spot' or 'on-demand'"
    exit 1
fi

echo "📝 Instance Configuration:"
echo "   Instance Type: $INSTANCE_TYPE"
echo "   AMI: $AMI_NAME"
echo "   Pricing: $PRICING"
if [ "$PRICING" = "spot" ]; then
    echo "   💰 Spot instance: 60-90% cheaper (persistent - can be stopped)"
fi
echo ""

# Check if instance already exists
EXISTING_INSTANCE=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null | head -1 || echo "")

if [ -n "$EXISTING_INSTANCE" ] && [ "$EXISTING_INSTANCE" != "None" ]; then
    echo "⚠️  Instance '$INSTANCE_NAME' already exists: $EXISTING_INSTANCE"
    echo "   Delete existing instance first or use a different name"
    exit 1
fi

# Get security group
SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --filters "Name=group-name,Values=$SECURITY_GROUP" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
    echo "❌ Security group '$SECURITY_GROUP' not found in $REGION"
    echo "   Create it first or update the script"
    exit 1
fi

# Find key file
KEY_FILE=""
if [ -f "$HOME/.ssh/${KEY_NAME}-${REGION}.pem" ]; then
    KEY_FILE="$HOME/.ssh/${KEY_NAME}-${REGION}.pem"
elif [ -f "$HOME/.ssh/${KEY_NAME}.pem" ]; then
    KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
else
    echo "❌ Key file not found. Checked:"
    echo "   - $HOME/.ssh/${KEY_NAME}-${REGION}.pem"
    echo "   - $HOME/.ssh/${KEY_NAME}.pem"
    exit 1
fi

echo "🔑 Using key file: $KEY_FILE"
echo ""

# Create instance from AMI
echo "📦 Creating instance from AMI..."
if [ "$PRICING" = "spot" ]; then
    # Spot instance - using "persistent" to allow stopping/starting
    RESULT=$(aws ec2 run-instances \
        --region $REGION \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_NAME \
        --security-group-ids $SG_ID \
        --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"persistent","InstanceInterruptionBehavior":"stop"}}' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
        --query 'Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone]' \
        --output text 2>&1)
else
    # On-demand instance
    RESULT=$(aws ec2 run-instances \
        --region $REGION \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_NAME \
        --security-group-ids $SG_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
        --query 'Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone]' \
        --output text 2>&1)
fi

if echo "$RESULT" | grep -q "i-[0-9a-f]"; then
    NEW_INSTANCE_ID=$(echo "$RESULT" | awk '{print $1}')
    STATE=$(echo "$RESULT" | awk '{print $2}')
    AZ=$(echo "$RESULT" | awk '{print $3}')
    
    echo "✅ Instance created successfully!"
    echo ""
    echo "📝 Instance Details:"
    echo "   Instance ID: $NEW_INSTANCE_ID"
    echo "   State: $STATE"
    echo "   Availability Zone: $AZ"
    echo "   Region: $REGION"
    echo "   Instance Type: $INSTANCE_TYPE"
    echo "   Pricing: $PRICING"
    if [ "$PRICING" = "spot" ]; then
        echo "   ⚠️  SPOT INSTANCE: Can be interrupted by AWS (but can be stopped/started)"
        echo "   💰 Cost: 60-90% cheaper than on-demand"
    fi
    echo ""
    echo "🔗 View in AWS Console:"
    echo "   https://console.aws.amazon.com/ec2/v2/home?region=$REGION#Instances:instanceId=$NEW_INSTANCE_ID"
    echo ""
    echo "⏳ Waiting for instance to be running..."
    aws ec2 wait instance-running \
        --region $REGION \
        --instance-ids $NEW_INSTANCE_ID 2>/dev/null || true
    
    sleep 5
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $NEW_INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "Not assigned yet")
    
    echo ""
    echo "📝 Network Details:"
    echo "   Public IP: $PUBLIC_IP"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
    echo ""
    echo "💡 Update management scripts:"
    echo "   The instance ID and region have been updated in management scripts"
    echo ""
    
    # Update region in other scripts
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for script in aws_start_instance.sh aws_stop_instance.sh aws_get_status.sh aws_delete_instance.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|REGION=\".*\"|REGION=\"$REGION\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
                sed -i '' "s|INSTANCE_ID=\".*\"|INSTANCE_ID=\"$NEW_INSTANCE_ID\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            else
                sed -i "s|REGION=\".*\"|REGION=\"$REGION\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
                sed -i "s|INSTANCE_ID=\".*\"|INSTANCE_ID=\"$NEW_INSTANCE_ID\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            fi
        fi
    done
    
else
    ERROR=$(echo "$RESULT" | grep -i "error\|denied\|unauthorized" || echo "$RESULT")
    echo "❌ Failed to create instance:"
    echo "   $ERROR"
    exit 1
fi

