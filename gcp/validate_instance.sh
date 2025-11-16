#!/bin/bash
# Validate GCP VM Instance Configuration
# This script checks if your instance is properly configured

set -e

PROJECT_ID="v2vbot"

echo "🔍 GCP Instance Validation Checklist"
echo "===================================="
echo ""

# Check current project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
echo "📋 Current Project: $CURRENT_PROJECT"
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "⚠️  Warning: Project mismatch!"
    echo "   Expected: $PROJECT_ID"
    echo "   Run: gcloud config set project $PROJECT_ID"
    echo ""
fi

# List all instances
echo "🔍 Checking for instances..."
INSTANCES=$(gcloud compute instances list --project=$PROJECT_ID --format="value(name,zone,status)" 2>/dev/null || echo "")

if [ -z "$INSTANCES" ]; then
    echo "❌ No instances found in project: $PROJECT_ID"
    echo ""
    echo "Possible reasons:"
    echo "1. Instance creation failed"
    echo "2. Instance created in different project"
    echo "3. Instance not created yet"
    echo ""
    echo "Check console: https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"
    exit 1
fi

echo "✅ Found instances:"
echo "$INSTANCES" | while IFS=$'\t' read -r name zone status; do
    echo "   - $name (Zone: $zone, Status: $status)"
    
    # Check instance details
    echo ""
    echo "📊 Checking instance: $name"
    echo "   Zone: $zone"
    
    # Get detailed info
    DETAILS=$(gcloud compute instances describe "$name" --zone="$zone" --project=$PROJECT_ID --format="table(
        name,
        status,
        machineType.scope(machineTypes):label=MACHINE_TYPE,
        networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP,
        accelerators[0].acceleratorType:label=GPU_TYPE,
        accelerators[0].acceleratorCount:label=GPU_COUNT
    )" 2>/dev/null)
    
    echo "$DETAILS"
    echo ""
    
    # Check GPU
    GPU_TYPE=$(gcloud compute instances describe "$name" --zone="$zone" --project=$PROJECT_ID --format="get(accelerators[0].acceleratorType)" 2>/dev/null || echo "None")
    if [ "$GPU_TYPE" != "None" ] && [ -n "$GPU_TYPE" ]; then
        echo "   ✅ GPU: $GPU_TYPE"
    else
        echo "   ⚠️  GPU: Not configured"
    fi
    
    # Check external IP
    EXTERNAL_IP=$(gcloud compute instances describe "$name" --zone="$zone" --project=$PROJECT_ID --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "None")
    if [ "$EXTERNAL_IP" != "None" ] && [ -n "$EXTERNAL_IP" ]; then
        echo "   ✅ External IP: $EXTERNAL_IP"
    else
        echo "   ⚠️  External IP: Not assigned"
    fi
    
    # Check firewall
    echo ""
    echo "🔒 Checking firewall rules..."
    FIREWALL=$(gcloud compute firewall-rules list --project=$PROJECT_ID --filter="targetTags:v2vbot-server OR allowed.ports:8080" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$FIREWALL" ]; then
        echo "   ✅ Firewall rules found"
    else
        echo "   ⚠️  No firewall rules for port 8080"
        echo "   Create with: gcloud compute firewall-rules create allow-v2vbot-http --allow tcp:8080 --source-ranges 0.0.0.0/0"
    fi
    
    echo ""
    echo "📝 Validation Summary for $name:"
    if [ "$status" = "RUNNING" ]; then
        echo "   ✅ Status: Running"
    else
        echo "   ⚠️  Status: $status"
    fi
    
    if [ "$GPU_TYPE" != "None" ] && [ -n "$GPU_TYPE" ]; then
        echo "   ✅ GPU configured"
    else
        echo "   ❌ GPU not configured"
    fi
    
    if [ "$EXTERNAL_IP" != "None" ] && [ -n "$EXTERNAL_IP" ]; then
        echo "   ✅ External IP assigned"
    else
        echo "   ⚠️  External IP not assigned"
    fi
    
    echo ""
done

echo "✅ Validation complete!"
echo ""
echo "Next steps:"
echo "1. If instance is running, SSH into it:"
echo "   gcloud compute ssh <instance-name> --zone=<zone>"
echo ""
echo "2. If GPU is missing, you'll need to recreate with GPU"
echo ""
echo "3. If firewall is missing, create firewall rule for port 8080"






