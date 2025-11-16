#!/bin/bash
# Start GCP VM instance
# Use this script to start the VM when you need to use it

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm"
ZONE="europe-west4-a"  # Netherlands, Europe region

echo "🚀 Starting GCP VM instance..."
echo ""

# Check if instance exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &>/dev/null; then
    echo "❌ Instance $INSTANCE_NAME not found in zone $ZONE"
    echo "   Create it first: ./gcp/gcp_create_vm.sh"
    exit 1
fi

# Check current status
STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(status)")

if [ "$STATUS" = "RUNNING" ]; then
    echo "✓ Instance is already running"
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    echo "   External IP: $EXTERNAL_IP"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    exit 0
fi

if [ "$STATUS" = "TERMINATED" ]; then
    echo "⚠️  Instance is terminated. Starting it up..."
    gcloud compute instances start $INSTANCE_NAME --zone=$ZONE
else
    echo "Starting instance (current status: $STATUS)..."
    gcloud compute instances start $INSTANCE_NAME --zone=$ZONE
fi

echo "⏳ Waiting for instance to be ready..."
sleep 10

# Wait for instance to be RUNNING
while [ "$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(status)")" != "RUNNING" ]; do
    echo "   Still starting... (status: $(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(status)"))"
    sleep 5
done

# Get the external IP
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "✅ Instance is now running!"
echo ""
echo "📝 Instance Details:"
echo "   Name: $INSTANCE_NAME"
echo "   Zone: $ZONE"
echo "   External IP: $EXTERNAL_IP"
echo ""
echo "🔗 Connect via SSH:"
echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo ""
echo "💰 Remember to stop the instance when done to save costs:"
echo "   ./gcp/gcp_stop_vm.sh"
echo ""

