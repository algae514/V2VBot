#!/bin/bash
# Start AWS EC2 instance
# Checks all regions to find the instance

set -e

INSTANCE_NAME="v2vbot-vm"

# All regions that create_instance tries
REGIONS=("ap-south-1" "ap-south-2" "eu-west-1" "us-east-1" "ap-southeast-1")

echo "🚀 Starting AWS EC2 instance..."
echo ""

# Find instance in all regions
INSTANCE_FOUND=false
FOUND_REGION="ap-south-1"
FOUND_INSTANCE_ID="i-04428b7e8ab12fd42"
FOUND_COUNT=0

for region in "${REGIONS[@]}"; do
    INSTANCE_ID=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null | head -1 || echo "")
    
    if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        if [ "$INSTANCE_FOUND" = false ]; then
            INSTANCE_FOUND=true
            FOUND_REGION="ap-south-1"
            FOUND_INSTANCE_ID="i-04428b7e8ab12fd42"
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
    echo ""
    echo "   Create it first: ./aws/aws_create_instance.sh"
    exit 1
fi

if [ "$FOUND_COUNT" -gt 1 ]; then
    echo "⚠️  WARNING: Found $FOUND_COUNT instances with name '$INSTANCE_NAME'!"
    echo "   Using instance in $FOUND_REGION. Consider deleting duplicates."
    echo ""
fi

REGION="ap-south-1"
INSTANCE_ID="i-04428b7e8ab12fd42"

# Check current status
STATUS=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

if [ "$STATUS" = "running" ]; then
    echo "✓ Instance is already running"
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "Not assigned")
    echo "   Instance ID: $INSTANCE_ID"
    echo "   Region: $REGION"
    echo "   Public IP: $PUBLIC_IP"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   ssh -i ~/.ssh/v2vbot-key.pem ubuntu@$PUBLIC_IP"
    exit 0
fi

if [ "$STATUS" = "stopped" ]; then
    echo "Starting instance (current status: stopped)..."
    aws ec2 start-instances --region $REGION --instance-ids $INSTANCE_ID
else
    echo "Starting instance (current status: $STATUS)..."
    aws ec2 start-instances --region $REGION --instance-ids $INSTANCE_ID
fi

echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

# Get the public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || echo "Not assigned yet")

echo ""
echo "✅ Instance is now running!"
echo ""
echo "📝 Instance Details:"
echo "   Instance ID: $INSTANCE_ID"
echo "   Region: $REGION"
echo "   Public IP: $PUBLIC_IP"
echo ""
echo "🔗 Connect via SSH:"
echo "   ssh -i ~/.ssh/v2vbot-key.pem ubuntu@$PUBLIC_IP"
echo ""
echo "💰 Remember to stop the instance when done to save costs:"
echo "   ./aws/aws_stop_instance.sh"
echo ""
