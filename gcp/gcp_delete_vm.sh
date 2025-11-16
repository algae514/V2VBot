#!/bin/bash
# Delete GCP VM instance
# WARNING: This will delete the VM and all data on the boot disk
# Use this only if you want to completely remove the instance

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm"
ZONE="europe-west4-a"  # Netherlands, Europe region

echo "⚠️  WARNING: This will delete the VM instance and all data on the boot disk!"
echo ""
echo "   Instance: $INSTANCE_NAME"
echo "   Zone: $ZONE"
echo ""

# Check if instance exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &>/dev/null; then
    echo "❌ Instance $INSTANCE_NAME not found in zone $ZONE"
    exit 1
fi

read -p "Are you sure you want to delete this instance? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🗑️  Deleting instance..."
gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --quiet

echo ""
echo "✅ Instance deleted successfully!"
echo ""
echo "💰 All charges stopped (including disk storage)"
echo ""
echo "🚀 To recreate the instance:"
echo "   ./gcp/gcp_create_vm.sh"
echo ""

