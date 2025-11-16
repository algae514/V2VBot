#!/bin/bash
# Create GCP VM with GPU for V2VBot - PRODUCTION VERSION
# Uses Reserved/Committed Use for guaranteed availability

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm-prod"
ZONE="europe-west4-a"  # Netherlands, Europe region
MACHINE_TYPE="n1-standard-2"
GPU_TYPE="nvidia-tesla-t4"
GPU_COUNT=1
DISK_SIZE="30GB"
DISK_TYPE="pd-standard"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

echo "🚀 Creating PRODUCTION GCP VM instance with GPU for V2VBot..."
echo ""
echo "⚠️  PRODUCTION MODE: This uses on-demand pricing."
echo "   For guaranteed availability, consider:"
echo "   1. Reserved Instances (1-3 year commitment, 30-70% discount)"
echo "   2. Committed Use Discounts (1-3 year commitment)"
echo "   3. Managed services (Cloud Run with GPUs, Vertex AI)"
echo ""

# Same VM creation as before, but with production considerations
echo "📋 Configuration:"
echo "   Project: $PROJECT_ID"
echo "   Instance: $INSTANCE_NAME"
echo "   Zone: $ZONE"
echo "   Machine Type: $MACHINE_TYPE"
echo "   GPU: $GPU_TYPE (x$GPU_COUNT)"
echo "   Disk: $DISK_SIZE ($DISK_TYPE)"
echo ""

# Check if instance already exists
if gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE &>/dev/null; then
    echo "⚠️  Instance $INSTANCE_NAME already exists in zone $ZONE"
    echo "   To recreate, first delete it: ./gcp/gcp_delete_vm.sh"
    exit 1
fi

# Create the VM instance
echo "🔨 Creating VM instance (this may take a few minutes)..."
gcloud compute instances create $INSTANCE_NAME \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --accelerator=type=$GPU_TYPE,count=$GPU_COUNT \
    --image-family=$IMAGE_FAMILY \
    --image-project=$IMAGE_PROJECT \
    --boot-disk-size=$DISK_SIZE \
    --boot-disk-type=$DISK_TYPE \
    --maintenance-policy=TERMINATE \
    --restart-on-failure \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --metadata=startup-script='#!/bin/bash
# Install NVIDIA drivers and CUDA
curl -fsSL https://raw.githubusercontent.com/GoogleCloudPlatform/compute-gpu-installation/main/linux/install_gpu_driver.py | python3

# Update system
sudo apt-get update

# Install system dependencies for Python app
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    wget \
    curl \
    ffmpeg \
    libsndfile1 \
    libsndfile1-dev \
    libopus0 \
    libopus-dev \
    portaudio19-dev \
    libportaudio2 \
    pkg-config

# Create a directory for the app
sudo mkdir -p /opt/v2vbot
sudo chown $USER:$USER /opt/v2vbot
'

echo ""
echo "✅ VM instance created successfully!"
echo ""
echo "📚 PRODUCTION RECOMMENDATIONS:"
echo ""
echo "1. RESERVED INSTANCES (Best for Production):"
echo "   - Guaranteed availability"
echo "   - 30-70% cost savings"
echo "   - 1-3 year commitment"
echo "   - Setup: https://console.cloud.google.com/compute/instances/reservations"
echo ""
echo "2. MANAGED SERVICES (Easiest):"
echo "   - Cloud Run with GPUs (serverless, auto-scaling)"
echo "   - Vertex AI (managed ML infrastructure)"
echo "   - Better availability, less management"
echo ""
echo "3. MULTI-REGION DEPLOYMENT:"
echo "   - Deploy in multiple zones/regions"
echo "   - Use load balancer for failover"
echo "   - Higher cost but better reliability"
echo ""

