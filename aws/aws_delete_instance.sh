#!/bin/bash
# Delete AWS EC2 instance
# Checks all regions to find the instance
# WARNING: This will delete the instance and all data on the EBS volume

set -e

INSTANCE_NAME="v2vbot-vm"

# All regions that create_instance tries
REGIONS=("ap-south-1" "ap-south-2" "eu-west-1" "us-east-1" "ap-southeast-1")

echo "⚠️  WARNING: This will delete the EC2 instance and all data on the EBS volume!"
echo ""

# Find ALL instances in all regions
FOUND_INSTANCES=()

for region in "${REGIONS[@]}"; do
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting,terminated" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Placement.AvailabilityZone]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_INFO" ] && [ "$INSTANCE_INFO" != "None" ]; then
        while IFS=$'\t' read -r inst_id state az; do
            if [ -n "$inst_id" ] && [ "$inst_id" != "None" ] && [ "$state" != "terminated" ]; then
                FOUND_INSTANCES+=("$region|$inst_id|$state|$az")
            fi
        done <<< "$INSTANCE_INFO"
    fi
done

if [ ${#FOUND_INSTANCES[@]} -eq 0 ]; then
    echo "❌ No instances found with name '$INSTANCE_NAME'"
    echo ""
    echo "   Regions checked:"
    for region in "${REGIONS[@]}"; do
        echo "     - $region"
    done
    exit 1
fi

echo "Found ${#FOUND_INSTANCES[@]} instance(s) to delete:"
for instance in "${FOUND_INSTANCES[@]}"; do
    IFS='|' read -r region inst_id state az <<< "$instance"
    echo "   - Region: $region, ID: $inst_id, State: $state, AZ: $az"
done
echo ""

read -p "Are you sure you want to delete ALL these instances? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🗑️  Deleting instances..."

# Delete all found instances
DELETED_COUNT=0
for instance in "${FOUND_INSTANCES[@]}"; do
    IFS='|' read -r region inst_id state az <<< "$instance"
    echo "   Deleting $inst_id in $region..."
    aws ec2 terminate-instances --region $region --instance-ids $inst_id &>/dev/null
    DELETED_COUNT=$((DELETED_COUNT + 1))
done

echo ""
echo "✅ Termination initiated for $DELETED_COUNT instance(s)!"
echo ""
echo "💰 All charges will stop once instances are fully terminated"
echo "   (EBS volumes will be deleted if configured to do so)"
echo ""
echo "🚀 To recreate the instance:"
echo "   ./aws/aws_create_instance.sh"
echo ""
