#!/bin/bash
# Stop AWS EC2 instance
# Checks all regions to find the instance

set -e

INSTANCE_NAME="v2vbot-vm"

# All regions that create_instance tries
REGIONS=("ap-south-1" "ap-south-2" "eu-west-1" "us-east-1" "ap-southeast-1")

echo "🛑 Stopping AWS EC2 instance to save costs..."
echo ""

# Find instance in all regions
INSTANCE_FOUND=false
FOUND_REGION=""
FOUND_INSTANCE_ID=""
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
            FOUND_REGION="$region"
            FOUND_INSTANCE_ID="$INSTANCE_ID"
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

if [ "$FOUND_COUNT" -gt 1 ]; then
    echo "⚠️  WARNING: Found $FOUND_COUNT instances with name '$INSTANCE_NAME'!"
    echo "   Stopping instance in $FOUND_REGION. Consider deleting duplicates."
    echo ""
fi

REGION="$FOUND_REGION"
INSTANCE_ID="$FOUND_INSTANCE_ID"

# Check current status
STATUS=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

if [ "$STATUS" = "stopped" ]; then
    echo "✓ Instance is already stopped"
    echo ""
    echo "💰 Cost savings:"
    echo "   - No compute charges while stopped"
    echo "   - Only EBS storage charges apply (~₹10/month for 30GB)"
    echo ""
    echo "🚀 To start the instance:"
    echo "   ./aws/aws_start_instance.sh"
    exit 0
fi

if [ "$STATUS" != "running" ]; then
    echo "⚠️  Instance status: $STATUS (not running, nothing to stop)"
    exit 0
fi

echo "Stopping instance..."
aws ec2 stop-instances --region $REGION --instance-ids $INSTANCE_ID

echo ""
echo "✅ Instance stopped successfully!"
echo ""
echo "💰 Cost savings:"
echo "   - No compute charges while stopped (saves ~₹70-150/hour depending on instance type)"
echo "   - Only EBS storage charges apply (~₹10/month for 30GB)"
echo ""
echo "🚀 To start the instance when needed:"
echo "   ./aws/aws_start_instance.sh"
echo ""
