#!/bin/bash
# Create GCP VM with GPU for V2VBot - ROBUST VERSION
# Tries multiple regions, GPU types, and preemptible instances to find availability

set -e

PROJECT_ID="v2vbot"
INSTANCE_NAME="v2vbot-vm"
DISK_SIZE="30GB"
DISK_TYPE="pd-standard"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

# Startup script for all instances
STARTUP_SCRIPT='#!/bin/bash
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

echo "🚀 Creating GCP VM instance with GPU for V2VBot (Robust Mode)..."
echo "   This script will try multiple regions, GPU types, and preemptible instances"
echo ""

# Check if project is set
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "⚠️  Project not set correctly. Run ./gcp/gcp_setup.sh first"
    exit 1
fi

# Check if instance already exists (check common zones)
EXISTING_INSTANCE=""
for zone in europe-west4-a europe-west4-b europe-west4-c asia-south1-a asia-south1-b us-central1-a; do
    if gcloud compute instances describe $INSTANCE_NAME --zone=$zone --project=$PROJECT_ID &>/dev/null; then
        EXISTING_INSTANCE="$zone"
        break
    fi
done

if [ -n "$EXISTING_INSTANCE" ]; then
    echo "⚠️  Instance $INSTANCE_NAME already exists in zone $EXISTING_INSTANCE"
    echo "   To recreate, first delete it: ./gcp/gcp_delete_vm.sh"
    exit 1
fi

# Define GPU configurations: (GPU_TYPE, MACHINE_TYPE, MIN_ZONES)
# Format: "gpu_type|machine_type|min_zones"
GPU_CONFIGS=(
    # T4 - Cost-effective, most common
    "nvidia-tesla-t4|n1-standard-2|europe-west4-a,europe-west4-b,europe-west4-c,asia-south1-a,asia-south1-b,us-central1-a,us-central1-b,us-central1-c"
    "nvidia-tesla-t4|n1-standard-4|europe-west4-a,europe-west4-b,europe-west4-c,asia-south1-a,asia-south1-b,us-central1-a,us-central1-b,us-central1-c"
    
    # A10 - More powerful, better availability sometimes
    "nvidia-tesla-a10|n1-standard-4|europe-west4-a,europe-west4-b,europe-west4-c,us-central1-a,us-central1-b"
    "nvidia-tesla-a10|n1-standard-8|europe-west4-a,europe-west4-b,europe-west4-c,us-central1-a,us-central1-b"
    
    # A100 - Most powerful, highest availability
    "nvidia-a100-80gb|n1-standard-8|europe-west4-a,europe-west4-b,us-central1-a,us-central1-b"
    "nvidia-a100-80gb|a2-highgpu-1g|europe-west4-a,europe-west4-b,us-central1-a,us-central1-b"
)

# Try regular instances first, then preemptible
INSTANCE_TYPES=("regular" "preemptible")

SUCCESS=false
CREATED_ZONE=""
CREATED_GPU=""
CREATED_MACHINE=""
CREATED_TYPE=""

echo "📋 Trying configurations in order of preference..."
echo ""

ATTEMPT=0
for instance_type in "${INSTANCE_TYPES[@]}"; do
    for gpu_config in "${GPU_CONFIGS[@]}"; do
        ATTEMPT=$((ATTEMPT + 1))
        
        IFS='|' read -r gpu_type machine_type zones <<< "$gpu_config"
        IFS=',' read -ra ZONE_ARRAY <<< "$zones"
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Attempt $ATTEMPT: $instance_type instance"
        echo "  GPU: $gpu_type"
        echo "  Machine: $machine_type"
        echo "  Zones: ${ZONE_ARRAY[@]}"
        echo ""
        
        # Try each zone for this configuration
        for zone in "${ZONE_ARRAY[@]}"; do
            echo "  Trying zone: $zone..."
            
            # Build gcloud command
            CMD="gcloud compute instances create $INSTANCE_NAME \
                --project=$PROJECT_ID \
                --zone=$zone \
                --machine-type=$machine_type \
                --accelerator=type=$gpu_type,count=1 \
                --image-family=$IMAGE_FAMILY \
                --image-project=$IMAGE_PROJECT \
                --boot-disk-size=$DISK_SIZE \
                --boot-disk-type=$DISK_TYPE \
                --maintenance-policy=TERMINATE \
                --restart-on-failure \
                --scopes=https://www.googleapis.com/auth/cloud-platform \
                --metadata=startup-script='$STARTUP_SCRIPT'"
            
            # Add preemptible flag if needed
            if [ "$instance_type" = "preemptible" ]; then
                CMD="$CMD --preemptible"
            fi
            
            # Try to create instance
            if eval "$CMD" > /tmp/gcp_create_output.log 2>&1; then
                SUCCESS=true
                CREATED_ZONE="$zone"
                CREATED_GPU="$gpu_type"
                CREATED_MACHINE="$machine_type"
                CREATED_TYPE="$instance_type"
                echo ""
                echo "✅ SUCCESS! Instance created!"
                # Break out of all loops
                break 2
            else
                ERROR=$(cat /tmp/gcp_create_output.log 2>/dev/null | grep -i "error\|exhausted\|quota\|not found\|denied" | head -1 || echo "")
                
                if echo "$ERROR" | grep -qi "quota\|limit"; then
                    echo "    ❌ Quota/limit issue - skipping this GPU type"
                    break  # Try next GPU type
                elif echo "$ERROR" | grep -qi "not found"; then
                    echo "    ❌ GPU type not available in this zone"
                    continue  # Try next zone
                elif echo "$ERROR" | grep -qi "exhausted"; then
                    echo "    ❌ Resources exhausted in this zone"
                    continue  # Try next zone
                elif echo "$ERROR" | grep -qi "denied\|permission"; then
                    echo "    ❌ Permission denied - skipping this zone"
                    continue  # Try next zone
                else
                    echo "    ❌ Failed (checking next zone...)"
                    continue  # Try next zone
                fi
            fi
        done
        
        # If we succeeded, break out of outer loop too
        if [ "$SUCCESS" = true ]; then
            break
        fi
        
        # Small delay between different GPU types
        sleep 1
    done
    
    # If we succeeded, break out of instance type loop
    if [ "$SUCCESS" = true ]; then
        break
    fi
    
    # If regular instances failed, try preemptible
    if [ "$SUCCESS" = false ] && [ "$instance_type" = "regular" ]; then
        echo ""
        echo "⚠️  Regular instances failed. Trying preemptible instances (60-90% cheaper)..."
        echo ""
    fi
done

# Final result
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$SUCCESS" = true ]; then
    echo "✅ VM instance created successfully!"
    echo ""
    echo "📝 Instance Details:"
    echo "   Name: $INSTANCE_NAME"
    echo "   Zone: $CREATED_ZONE"
    echo "   Machine Type: $CREATED_MACHINE"
    echo "   GPU: $CREATED_GPU"
    echo "   Type: $CREATED_TYPE"
    if [ "$CREATED_TYPE" = "preemptible" ]; then
        echo "   ⚠️  PREEMPTIBLE: Can be terminated by GCP (max 24h runtime)"
        echo "   💰 Cost: 60-90% cheaper than regular instances"
    fi
    echo ""
    
    # Wait a bit for instance to initialize
    echo "⏳ Waiting for instance to initialize (30 seconds)..."
    sleep 30
    
    # Get the external IP
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$CREATED_ZONE --project=$PROJECT_ID --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not assigned yet")
    
    echo ""
    echo "📝 Network Details:"
    echo "   External IP: $EXTERNAL_IP"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   gcloud compute ssh $INSTANCE_NAME --zone=$CREATED_ZONE"
    echo ""
    
    # Update zone in other scripts for convenience
    echo "💡 Updating zone in management scripts..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for script in gcp_start_vm.sh gcp_stop_vm.sh gcp_get_status.sh gcp_delete_vm.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed syntax
                sed -i '' "s|ZONE=\".*\"|ZONE=\"$CREATED_ZONE\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            else
                # Linux sed syntax
                sed -i "s|ZONE=\".*\"|ZONE=\"$CREATED_ZONE\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            fi
        fi
    done
    echo "   ✅ Zone updated in management scripts to: $CREATED_ZONE"
    echo ""
    
    # Cost information
    echo "💰 Cost Information:"
    if [ "$CREATED_TYPE" = "preemptible" ]; then
        echo "   - Preemptible instance: 60-90% cheaper"
        echo "   - Estimated: ~₹15-30/hour (~$0.18-0.36/hour)"
    else
        case "$CREATED_GPU" in
            nvidia-tesla-t4)
                echo "   - T4 GPU: ~₹73/hour (~$0.90/hour)"
                ;;
            nvidia-tesla-a10)
                echo "   - A10 GPU: ~₹150-200/hour (~$1.80-2.40/hour)"
                ;;
            nvidia-a100-80gb)
                echo "   - A100 GPU: ~₹300-400/hour (~$3.60-4.80/hour)"
                ;;
        esac
    fi
    echo "   - Disk storage: ~₹15/month (~$0.18/month) for 30GB"
    echo "   - Stop VM when not in use: ./gcp/gcp_stop_vm.sh"
    echo "   - Start VM when needed: ./gcp/gcp_start_vm.sh"
    echo ""
    
    echo "📚 Next steps:"
    echo "   1. SSH into the instance: gcloud compute ssh $INSTANCE_NAME --zone=$CREATED_ZONE"
    echo "   2. Clone your repository: git clone <your-repo-url> V2VBot"
    echo "   3. Setup and run: cd V2VBot && cp env.example .env && bash setup_server.sh"
    echo "   4. Or manually: python3 -m venv venv && source venv/bin/activate && pip install -r server/requirements.txt"
    echo "   5. Start server: python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080"
    echo ""
    
    if [ "$CREATED_TYPE" = "preemptible" ]; then
        echo "⚠️  IMPORTANT: Preemptible instances can be terminated by GCP at any time."
        echo "   - Maximum runtime: 24 hours"
        echo "   - Not suitable for production workloads requiring high availability"
        echo "   - Great for development, testing, or cost-sensitive workloads"
        echo ""
    fi
    
else
    echo "❌ Failed to create instance after trying all configurations"
    echo ""
    echo "💡 Suggestions:"
    echo "   1. Try again later (availability changes frequently)"
    echo "   2. Request GPU quota increase:"
    echo "      https://console.cloud.google.com/iam-admin/quotas?project=$PROJECT_ID"
    echo "   3. Try creating manually from console:"
    echo "      https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"
    echo "   4. Check console guide: docs/gcp-console-guide.md"
    echo ""
    echo "📊 What was tried:"
    echo "   - Regular instances: T4, A10, A100 in multiple zones"
    echo "   - Preemptible instances: T4, A10, A100 in multiple zones"
    echo "   - Regions: Europe, Asia, US"
    echo ""
    exit 1
fi
