#!/bin/bash
# Get status of GCP VM instance

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm"
ZONE="europe-west4-a"  # Netherlands, Europe region

echo "📊 GCP VM Instance Status"
echo ""

# Check if instance exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &>/dev/null; then
    echo "❌ Instance $INSTANCE_NAME not found in zone $ZONE"
    echo "   Create it first: ./gcp/gcp_create_vm.sh"
    exit 1
fi

# Get instance details
STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(status)")
MACHINE_TYPE=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(machineType)" | awk -F'/' '{print $NF}')
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)" || echo "None")
INTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format="get(networkInterfaces[0].networkIP)")

echo "Instance: $INSTANCE_NAME"
echo "Zone: $ZONE"
echo "Status: $STATUS"
echo "Machine Type: $MACHINE_TYPE"
echo "Internal IP: $INTERNAL_IP"
echo "External IP: $EXTERNAL_IP"
echo ""

if [ "$STATUS" = "RUNNING" ]; then
    echo "✅ Instance is running"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    echo ""
    echo "💰 Cost (India Region): ~₹73/hour (~$0.90/hour) while running"
    echo "   Stop when done: ./gcp/gcp_stop_vm.sh"
elif [ "$STATUS" = "TERMINATED" ]; then
    echo "⏸️  Instance is stopped"
    echo ""
    echo "💰 Cost (India Region): Only disk storage charges apply (~₹15/month for 30GB)"
    echo "   Start when needed: ./gcp/gcp_start_vm.sh"
else
    echo "⚠️  Instance status: $STATUS"
fi
echo ""

