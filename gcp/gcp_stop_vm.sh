#!/bin/bash
# Stop GCP VM instance
# Use this script to stop the VM and save costs when not in use

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm"
ZONE="europe-west4-a"  # Netherlands, Europe region

echo "🛑 Stopping GCP VM instance to save costs..."
echo ""

# Check if instance exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &>/dev/null; then
    echo "❌ Instance $INSTANCE_NAME not found in zone $ZONE"
    exit 1
fi

# Check current status
STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(status)")

if [ "$STATUS" = "TERMINATED" ]; then
    echo "✓ Instance is already stopped"
    echo ""
    echo "💰 Cost savings (India Region):"
    echo "   - No compute charges while stopped (saves ~₹73/hour)"
    echo "   - Only disk storage charges apply (~₹15/month for 30GB)"
    echo ""
    echo "🚀 To start the instance:"
    echo "   ./gcp/gcp_start_vm.sh"
    exit 0
fi

if [ "$STATUS" != "RUNNING" ]; then
    echo "⚠️  Instance status: $STATUS (not running, nothing to stop)"
    exit 0
fi

echo "Stopping instance..."
gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE

echo ""
echo "✅ Instance stopped successfully!"
echo ""
echo "💰 Cost savings (India Region):"
echo "   - No compute charges while stopped (saves ~₹73/hour)"
echo "   - Only disk storage charges apply (~₹15/month for 30GB)"
echo ""
echo "🚀 To start the instance when needed:"
echo "   ./gcp/gcp_start_vm.sh"
echo ""

