#!/bin/bash
# GCP Setup Script for V2VBot
# This script sets up GCP authentication and project configuration

set -e

PROJECT_ID="v2vbot"
ZONE="europe-west4-a"  # Netherlands, Europe region (better GPU availability)
REGION="europe-west4"

echo "🚀 Setting up GCP for V2VBot..."
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install --cask google-cloud-sdk
    else
        echo "Please install gcloud CLI manually: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
fi

echo "✓ gcloud CLI found"

# Initialize gcloud if not already initialized
if ! gcloud config list --format="value(core.account)" &> /dev/null; then
    echo ""
    echo "📝 Initializing gcloud..."
    gcloud init
else
    echo "✓ gcloud already initialized"
fi

# Set the project
echo ""
echo "📋 Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Set default zone and region
echo "📍 Setting default zone to $ZONE..."
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

# Enable required APIs
echo ""
echo "🔌 Enabling required GCP APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Verify authentication
echo ""
echo "🔐 Verifying authentication..."
CURRENT_ACCOUNT=$(gcloud config get-value account)
CURRENT_PROJECT=$(gcloud config get-value project)

echo "✓ Authenticated as: $CURRENT_ACCOUNT"
echo "✓ Current project: $CURRENT_PROJECT"

if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "⚠️  Warning: Project mismatch. Expected $PROJECT_ID, got $CURRENT_PROJECT"
    echo "   Run: gcloud config set project $PROJECT_ID"
fi

echo ""
echo "✅ GCP setup complete!"
echo ""
echo "Next steps:"
echo "1. Run: ./gcp/gcp_create_vm.sh to create the VM instance"
echo "2. Run: ./gcp/gcp_start_vm.sh to start the VM when needed"
echo "3. Run: ./gcp/gcp_stop_vm.sh to stop the VM and save costs"
echo ""

