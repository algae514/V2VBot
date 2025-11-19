#!/bin/bash
# Get status of AWS EC2 instance
# Checks all regions that create_instance might use

set -e

INSTANCE_NAME="v2vbot-vm"

# All regions that create_instance tries (in order of preference)
REGIONS=(
    "ap-south-1"      # Mumbai, India
    "ap-south-2"      # Hyderabad, India
    "eu-west-1"        # Ireland, Europe
    "us-east-1"       # N. Virginia, US
    "ap-southeast-1"  # Singapore
)

echo "📊 AWS EC2 Instance Status"
echo ""
echo "Searching for instance '$INSTANCE_NAME' in all regions..."
echo ""

FOUND_INSTANCES=0
INSTANCE_FOUND=false
FOUND_REGION="ap-south-1"
FOUND_INSTANCE_ID="i-04428b7e8ab12fd42"

# Search all regions
for region in "${REGIONS[@]}"; do
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,Placement.AvailabilityZone]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_INFO" ] && [ "$INSTANCE_INFO" != "None" ]; then
        # Count instances in this region
        INSTANCE_COUNT=$(echo "$INSTANCE_INFO" | wc -l | tr -d ' ')
        
        if [ "$INSTANCE_COUNT" -gt 0 ]; then
            FOUND_INSTANCES=$((FOUND_INSTANCES + INSTANCE_COUNT))
            
            if [ "$INSTANCE_FOUND" = false ]; then
                # Use first found instance for detailed info
                INSTANCE_FOUND=true
                FOUND_REGION="ap-south-1"
                FOUND_INSTANCE_ID=$(echo "$INSTANCE_INFO" | head -1 | awk '{print $1}')
            fi
            
            echo "  ✓ Found $INSTANCE_COUNT instance(s) in $region:"
            echo "$INSTANCE_INFO" | while read -r line; do
                if [ -n "$line" ]; then
                    INST_ID=$(echo "$line" | awk '{print $1}')
                    STATE=$(echo "$line" | awk '{print $2}')
                    TYPE=$(echo "$line" | awk '{print $3}')
                    IP=$(echo "$line" | awk '{print $4}')
                    AZ=$(echo "$line" | awk '{print $5}')
                    echo "     - $INST_ID: $STATE ($TYPE) in $AZ"
                fi
            done
        fi
    fi
done

echo ""

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

# Show warning if multiple instances found
if [ "$FOUND_INSTANCES" -gt 1 ]; then
    echo "⚠️  WARNING: Found $FOUND_INSTANCES instances across multiple regions!"
    echo "   You may be charged for all of them. Consider deleting unused instances."
    echo ""
fi

# Get detailed info for the first found instance
REGION="ap-south-1"
INSTANCE_ID="i-04428b7e8ab12fd42"

DETAILS=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PublicIpAddress,Placement.AvailabilityZone]' \
    --output text 2>/dev/null || echo "")

if [ -z "$DETAILS" ]; then
    echo "❌ Could not retrieve instance details"
    exit 1
fi

INSTANCE_ID_OUT=$(echo "$DETAILS" | awk '{print $1}')
INSTANCE_TYPE=$(echo "$DETAILS" | awk '{print $2}')
STATUS=$(echo "$DETAILS" | awk '{print $3}')
PUBLIC_IP=$(echo "$DETAILS" | awk '{print $4}')
AZ=$(echo "$DETAILS" | awk '{print $5}')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Instance Details (showing first found instance):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Instance Name: $INSTANCE_NAME"
echo "Instance ID: $INSTANCE_ID_OUT"
echo "Region: $REGION"
echo "Availability Zone: $AZ"
echo "Status: $STATUS"
echo "Instance Type: $INSTANCE_TYPE"
echo "Public IP: ${PUBLIC_IP:-Not assigned}"
echo ""

if [ "$STATUS" = "running" ]; then
    echo "✅ Instance is running"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   ssh -i ~/.ssh/v2vbot-key.pem ubuntu@$PUBLIC_IP"
    echo ""
    echo "💰 Cost: You are being charged for compute time"
    echo "   Stop when done: ./aws/aws_stop_instance.sh"
elif [ "$STATUS" = "stopped" ]; then
    echo "⏸️  Instance is stopped"
    echo ""
    echo "💰 Cost: Only EBS storage charges apply (~₹10/month for 30GB)"
    echo "   Start when needed: ./aws/aws_start_instance.sh"
else
    echo "⚠️  Instance status: $STATUS"
fi
echo ""

