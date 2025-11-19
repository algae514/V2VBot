#!/bin/bash
# Create AWS EC2 instance with GPU for V2VBot - ROBUST VERSION
# Tries multiple regions, instance types, and spot instances to find availability
#
# To use a custom AMI (e.g., from a backup), use:
#   ./aws/aws_create_instance_from_ami.sh
# Or set CUSTOM_AMI_ID below to use your saved AMI instead of fresh Ubuntu

set -e

INSTANCE_NAME="v2vbot-vm"
KEY_NAME="v2vbot-key"  # You'll need to create this or use existing key
SECURITY_GROUP="v2vbot-sg"
DISK_SIZE=30
IMAGE_ID=""  # Will be set based on region (Ubuntu 22.04 LTS)

# Optional: Set this to use your saved AMI instead of creating fresh Ubuntu instance
# Example: CUSTOM_AMI_ID="ami-068fbb4aeefb15ebc"
# Note: For using saved AMIs, it's recommended to use: ./aws/aws_create_instance_from_ami.sh
CUSTOM_AMI_ID=""

# Startup script for all instances
USER_DATA='#!/bin/bash
# Install NVIDIA drivers and CUDA
sudo apt-get update
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Install CUDA toolkit
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-1

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
sudo chown ubuntu:ubuntu /opt/v2vbot || sudo chown ec2-user:ec2-user /opt/v2vbot
'

echo "🚀 Creating AWS EC2 instance with GPU for V2VBot (Robust Mode)..."
echo "   This script will try multiple regions, instance types, and spot instances"
echo ""

# Check AWS authentication
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS not authenticated. Run ./aws/aws_setup.sh first"
    exit 1
fi

# Function to find the correct key file (check region-specific first, then generic)
find_key_file() {
    local region=$1
    local region_specific_key="$HOME/.ssh/${KEY_NAME}-${region}.pem"
    local generic_key="$HOME/.ssh/${KEY_NAME}.pem"
    
    # Check for region-specific key first
    if [ -f "$region_specific_key" ]; then
        echo "$region_specific_key"
        return 0
    # Fall back to generic key
    elif [ -f "$generic_key" ]; then
        echo "$generic_key"
        return 0
    else
        return 1
    fi
}

# Check if local key file exists (try primary region first)
PRIMARY_REGION="ap-south-1"
KEY_FILE=$(find_key_file "$PRIMARY_REGION" || echo "")

if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "❌ Key file not found. Checked:"
    echo "   - $HOME/.ssh/${KEY_NAME}-${PRIMARY_REGION}.pem"
    echo "   - $HOME/.ssh/${KEY_NAME}.pem"
    echo ""
    echo "   Create the key pair first:"
    echo "   aws ec2 create-key-pair --region $PRIMARY_REGION --key-name $KEY_NAME --query 'KeyMaterial' --output text > $HOME/.ssh/${KEY_NAME}-${PRIMARY_REGION}.pem"
    echo "   chmod 400 $HOME/.ssh/${KEY_NAME}-${PRIMARY_REGION}.pem"
    echo ""
    exit 1
fi

echo "🔑 Using key file: $KEY_FILE"

# Function to ensure key pair exists in a region (import if needed)
ensure_key_in_region() {
    local region=$1
    local key_file_to_use="$KEY_FILE"
    
    # Try to find region-specific key file for this region
    local region_specific_key="$HOME/.ssh/${KEY_NAME}-${region}.pem"
    if [ -f "$region_specific_key" ]; then
        key_file_to_use="$region_specific_key"
    fi
    
    if aws ec2 describe-key-pairs --region $region --key-names $KEY_NAME &>/dev/null; then
        return 0  # Key exists
    fi
    
    # Import key to region
    PUBLIC_KEY=$(ssh-keygen -y -f "$key_file_to_use" 2>/dev/null || echo "")
    if [ -z "$PUBLIC_KEY" ]; then
        return 1  # Failed to extract public key
    fi
    
    aws ec2 import-key-pair \
        --region $region \
        --key-name $KEY_NAME \
        --public-key-material "$PUBLIC_KEY" \
        --output text &>/dev/null
    
    return $?
}

# Ensure key exists in primary region (will be used first)
echo "🔑 Ensuring key pair '$KEY_NAME' is available..."
if ! ensure_key_in_region "ap-south-2"; then
    echo "   ⚠️  Could not import key to ap-south-2, will try during instance creation"
fi
echo ""

# Check if instance already exists in ANY region
echo "🔍 Checking for existing instances with name '$INSTANCE_NAME'..."
EXISTING_INSTANCES=()
REGIONS_TO_CHECK=("ap-south-1" "ap-south-2" "eu-west-1" "us-east-1" "ap-southeast-1")

for region in "${REGIONS_TO_CHECK[@]}"; do
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,starting" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Placement.AvailabilityZone]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_INFO" ] && [ "$INSTANCE_INFO" != "None" ]; then
        while IFS=$'\t' read -r inst_id state az; do
            if [ -n "$inst_id" ] && [ "$inst_id" != "None" ]; then
                EXISTING_INSTANCES+=("$region|$inst_id|$state|$az")
            fi
        done <<< "$INSTANCE_INFO"
    fi
done

if [ ${#EXISTING_INSTANCES[@]} -gt 0 ]; then
    echo "⚠️  Instance(s) with name '$INSTANCE_NAME' already exist:"
    for instance in "${EXISTING_INSTANCES[@]}"; do
        IFS='|' read -r region inst_id state az <<< "$instance"
        echo "   - Region: $region, ID: $inst_id, State: $state, AZ: $az"
    done
    echo ""
    echo "   Delete existing instance(s) first or use a different name"
    echo "   Delete command: ./aws/aws_delete_instance.sh"
    exit 1
fi
echo "   ✓ No existing instances found"
echo ""

# Global array to store available instance types
AVAILABLE_TYPES=()

# Function to get available spot instance types in a region
get_available_spot_instances() {
    local region=$1
    local instance_families=("g" "vt")  # G and VT families based on quota
    
    echo "🔍 Querying available spot instance types in $region..."
    
    AVAILABLE_TYPES=()
    
    # Get all instance type offerings for the region
    INSTANCE_OFFERINGS=$(aws ec2 describe-instance-type-offerings \
        --region $region \
        --location-type region \
        --query 'InstanceTypeOfferings[*].InstanceType' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$INSTANCE_OFFERINGS" ]; then
        echo "   ⚠️  Could not query instance offerings for $region"
        return 1
    fi
    
    # Filter for G and VT families and check spot pricing
    for family in "${instance_families[@]}"; do
        # Get all instance types starting with the family prefix
        FAMILY_TYPES=$(echo "$INSTANCE_OFFERINGS" | tr ' ' '\n' | grep "^${family}" | sort -V)
        
        for instance_type in $FAMILY_TYPES; do
            # Check if spot pricing is available for this instance type
            SPOT_PRICE=$(aws ec2 describe-spot-price-history \
                --region $region \
                --instance-types $instance_type \
                --product-descriptions "Linux/UNIX" \
                --max-items 1 \
                --query 'SpotPriceHistory[0].SpotPrice' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$SPOT_PRICE" ] && [ "$SPOT_PRICE" != "None" ] && [ "$SPOT_PRICE" != "" ]; then
                AVAILABLE_TYPES+=("$instance_type")
                echo "   ✓ Found: $instance_type (Spot price: $SPOT_PRICE USD/hour)"
            fi
        done
    done
    
    if [ ${#AVAILABLE_TYPES[@]} -eq 0 ]; then
        echo "   ⚠️  No G or VT spot instances available in $region"
        return 1
    fi
    
    echo "   ✓ Found ${#AVAILABLE_TYPES[@]} available spot instance type(s)"
    return 0
}

# Function to get GPU type for an instance type
get_gpu_type() {
    local instance_type=$1
    case $instance_type in
        g4dn.*)
            echo "NVIDIA T4"
            ;;
        g5.*)
            echo "NVIDIA A10G"
            ;;
        g6.*)
            echo "NVIDIA L4"
            ;;
        vt1.*)
            echo "NVIDIA T4"
            ;;
        *)
            echo "GPU"
            ;;
    esac
}

# Query available instances in primary region (ap-south-1)
PRIMARY_REGION="ap-south-1"
echo "📋 Checking available spot instance types in $PRIMARY_REGION..."
echo ""

if get_available_spot_instances "$PRIMARY_REGION"; then
    echo ""
    echo "✅ Building instance configurations from available types..."
    
    # Build INSTANCE_CONFIGS dynamically from available types
    INSTANCE_CONFIGS=()
    
    # Prioritize common sizes: xlarge, 2xlarge, 4xlarge, large
    PRIORITY_SIZES=("xlarge" "2xlarge" "4xlarge" "large" "8xlarge" "12xlarge" "16xlarge" "24xlarge")
    
    for size in "${PRIORITY_SIZES[@]}"; do
        for instance_type in "${AVAILABLE_TYPES[@]}"; do
            if [[ "$instance_type" == *"$size" ]]; then
                GPU_TYPE=$(get_gpu_type "$instance_type")
                # Prioritize ap-south-1, but also try other regions
                INSTANCE_CONFIGS+=("$instance_type|$GPU_TYPE|ap-south-1,ap-south-2,eu-west-1,us-east-1,ap-southeast-1")
            fi
        done
    done
    
    # Add any remaining types that don't match priority sizes
    for instance_type in "${AVAILABLE_TYPES[@]}"; do
        MATCHED=false
        for size in "${PRIORITY_SIZES[@]}"; do
            if [[ "$instance_type" == *"$size" ]]; then
                MATCHED=true
                break
            fi
        done
        if [ "$MATCHED" = false ]; then
            GPU_TYPE=$(get_gpu_type "$instance_type")
            INSTANCE_CONFIGS+=("$instance_type|$GPU_TYPE|ap-south-1,ap-south-2,eu-west-1,us-east-1,ap-southeast-1")
        fi
    done
    
    echo "   ✓ Configured ${#INSTANCE_CONFIGS[@]} instance type(s) to try"
    echo ""
else
    echo ""
    echo "⚠️  Could not query available instances. Falling back to default configurations..."
    echo ""
    
    # Fallback to default configurations (G family only, no P family)
    INSTANCE_CONFIGS=(
        # g4dn - T4 GPU, cost-effective
        "g4dn.xlarge|NVIDIA T4|ap-south-1,ap-south-2,eu-west-1,us-east-1,ap-southeast-1"
        "g4dn.2xlarge|NVIDIA T4|ap-south-1,ap-south-2,eu-west-1,us-east-1,ap-southeast-1"
        
        # g5 - A10G GPU, more powerful
        "g5.xlarge|NVIDIA A10G|ap-south-1,ap-south-2,eu-west-1,us-east-1"
        "g5.2xlarge|NVIDIA A10G|ap-south-1,ap-south-2,eu-west-1,us-east-1"
    )
fi

# Try spot instances first (cheaper), then on-demand
INSTANCE_TYPES=("spot" "on-demand")

SUCCESS=false
CREATED_INSTANCE_ID=""
CREATED_REGION=""
CREATED_INSTANCE_TYPE=""
CREATED_GPU=""
CREATED_INSTANCE_FAMILY=""

echo "📋 Trying configurations in order of preference..."
echo ""

ATTEMPT=0
for instance_pricing in "${INSTANCE_TYPES[@]}"; do
    for config in "${INSTANCE_CONFIGS[@]}"; do
        ATTEMPT=$((ATTEMPT + 1))
        
        IFS='|' read -r instance_family gpu_type regions <<< "$config"
        IFS=',' read -ra REGION_ARRAY <<< "$regions"
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Attempt $ATTEMPT: $instance_pricing instance"
        echo "  Instance Type: $instance_family"
        echo "  GPU: $gpu_type"
        echo "  Regions: ${REGION_ARRAY[@]}"
        echo ""
        
        # Try each region for this configuration
        for region in "${REGION_ARRAY[@]}"; do
            echo "  Trying region: $region..."
            
            # Get Ubuntu 22.04 LTS AMI for this region
            IMAGE_ID=$(aws ec2 describe-images \
                --region $region \
                --owners 099720109477 \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
                --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
                --output text 2>/dev/null || echo "")
            
            if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "None" ]; then
                echo "    ❌ Could not find Ubuntu AMI in $region"
                continue
            fi
            
            # Create or get security group
            SG_ID=$(aws ec2 describe-security-groups \
                --region $region \
                --filters "Name=group-name,Values=$SECURITY_GROUP" \
                --query 'SecurityGroups[0].GroupId' \
                --output text 2>/dev/null || echo "")
            
            if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
                echo "    Creating security group..."
                SG_OUTPUT=$(aws ec2 create-security-group \
                    --region $region \
                    --group-name $SECURITY_GROUP \
                    --description "Security group for V2VBot" \
                    --output text 2>&1)
                
                if echo "$SG_OUTPUT" | grep -q "sg-"; then
                    SG_ID=$(echo "$SG_OUTPUT" | grep -o "sg-[a-z0-9]*" | head -1)
                    
                    # Allow SSH and HTTP
                    aws ec2 authorize-security-group-ingress \
                        --region $region \
                        --group-id $SG_ID \
                        --protocol tcp \
                        --port 22 \
                        --cidr 0.0.0.0/0 &>/dev/null || true
                    
                    aws ec2 authorize-security-group-ingress \
                        --region $region \
                        --group-id $SG_ID \
                        --protocol tcp \
                        --port 8080 \
                        --cidr 0.0.0.0/0 &>/dev/null || true
                    
                    echo "    ✓ Security group created: $SG_ID"
                else
                    echo "    ❌ Failed to create security group"
                    continue
                fi
            else
                echo "    ✓ Using existing security group: $SG_ID"
            fi
            
            # Encode user data to base64
            USER_DATA_B64=$(echo -n "$USER_DATA" | base64)
            
            # Build block device mapping JSON
            BLOCK_DEVICE="[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_SIZE,\"VolumeType\":\"gp3\"}}]"
            
            # Try to create instance
            echo "    Submitting instance creation request..."
            if [ "$instance_pricing" = "spot" ]; then
                # Spot instance - using "persistent" to allow stopping/starting
                RESULT=$(aws ec2 run-instances \
                    --region $region \
                    --image-id $IMAGE_ID \
                    --instance-type $instance_family \
                    --key-name $KEY_NAME \
                    --security-group-ids $SG_ID \
                    --block-device-mappings "$BLOCK_DEVICE" \
                    --user-data "$USER_DATA_B64" \
                    --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"persistent","InstanceInterruptionBehavior":"stop"}}' \
                    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
                    --query 'Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone]' \
                    --output text 2>&1)
            else
                # On-demand instance
                RESULT=$(aws ec2 run-instances \
                    --region $region \
                    --image-id $IMAGE_ID \
                    --instance-type $instance_family \
                    --key-name $KEY_NAME \
                    --security-group-ids $SG_ID \
                    --block-device-mappings "$BLOCK_DEVICE" \
                    --user-data "$USER_DATA_B64" \
                    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
                    --query 'Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone]' \
                    --output text 2>&1)
            fi
            
            # Show the result immediately
            if [ -n "$RESULT" ]; then
                # Check if it's an error or success
                if echo "$RESULT" | grep -qi "error\|An error occurred"; then
                    echo "    ❌ Error response received"
                elif echo "$RESULT" | grep -q "i-[0-9a-f]"; then
                    echo "    ✓ Success response received"
                else
                    echo "    Response: $(echo "$RESULT" | head -1 | cut -c1-100)"
                fi
            else
                echo "    ⚠️  No response received (command may have hung)"
            fi
            
            # Check for errors BEFORE checking for success
            ERROR=$(echo "$RESULT" | grep -i "error\|unsupported\|not available\|not supported\|InvalidKeyPair\|NotFound\|MaxSpotInstanceCountExceeded\|SpotInstanceCountExceeded\|PendingVerification\|VcpuLimitExceeded\|LimitExceeded\|QuotaExceeded" || true)
            if [ -n "$ERROR" ]; then
                # Handle key pair not found - import from existing key
                if echo "$ERROR" | grep -qi "InvalidKeyPair\|key.*not found"; then
                    echo "    ⚠️  Key pair '$KEY_NAME' not found in $region, importing..."
                    
                    if [ -f "$KEY_FILE" ]; then
                        PUBLIC_KEY=$(ssh-keygen -y -f "$KEY_FILE" 2>/dev/null || echo "")
                        
                        if [ -n "$PUBLIC_KEY" ]; then
                            IMPORT_RESULT=$(aws ec2 import-key-pair \
                                --region $region \
                                --key-name $KEY_NAME \
                                --public-key-material "$PUBLIC_KEY" \
                                --output text 2>&1)
                            
                            if echo "$IMPORT_RESULT" | grep -q "key-fingerprint\|$KEY_NAME"; then
                                echo "    ✓ Key pair imported to $region"
                                # Retry instance creation - continue to next iteration
                                continue
                            else
                                echo "    ❌ Failed to import: $IMPORT_RESULT"
                                continue
                            fi
                        else
                            echo "    ❌ Could not extract public key from $KEY_FILE"
                            continue
                        fi
                    else
                        echo "    ❌ Key file not found: $KEY_FILE"
                        continue
                    fi
                elif echo "$ERROR" | grep -qi "MaxSpotInstanceCountExceeded\|SpotInstanceCountExceeded"; then
                    echo "    ❌ Spot instance limit exceeded - will try on-demand next"
                    # Break to try on-demand instances
                    break
                elif echo "$ERROR" | grep -qi "PendingVerification"; then
                    echo "    ⚠️  Account verification pending for $region (new account)"
                    echo "    Trying next region..."
                    continue
                elif echo "$ERROR" | grep -qi "VcpuLimitExceeded\|LimitExceeded\|QuotaExceeded"; then
                    echo "    ❌ vCPU/Quota limit exceeded in $region"
                    echo "    Your account has insufficient quota to create this instance type"
                    echo "    Request quota increase: https://console.aws.amazon.com/servicequotas/home"
                    echo "    Trying next region..."
                    continue
                else
                    echo "    ❌ Failed: $ERROR"
                    continue
                fi
            fi
            
            if echo "$RESULT" | grep -q "i-[0-9a-f]"; then
                # Success!
                INSTANCE_ID=$(echo "$RESULT" | awk '{print $1}')
                STATE=$(echo "$RESULT" | awk '{print $2}')
                AZ=$(echo "$RESULT" | awk '{print $3}')
                
                SUCCESS=true
                CREATED_INSTANCE_ID="$INSTANCE_ID"
                CREATED_REGION="$region"
                CREATED_INSTANCE_TYPE="$instance_pricing"
                CREATED_GPU="$gpu_type"
                CREATED_INSTANCE_FAMILY="$instance_family"
                
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "✅ SUCCESS! Instance creation request SUBMITTED to AWS!"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "📝 Request Details:"
                echo "   Instance ID: $INSTANCE_ID"
                echo "   State: $STATE"
                echo "   Availability Zone: $AZ"
                echo "   Region: $region"
                echo "   Instance Type: $instance_family"
                echo "   GPU: $gpu_type"
                echo "   Pricing: $instance_pricing"
                echo ""
                echo "🔗 View in AWS Console (click to verify):"
                echo "   https://console.aws.amazon.com/ec2/v2/home?region=$region#Instances:instanceId=$INSTANCE_ID"
                echo ""
                echo "⏳ Instance is now being created. This may take 1-2 minutes..."
                echo ""
                break 2
            else
                ERROR=$(echo "$RESULT" | grep -i "error\|insufficient\|unavailable\|limit" | head -1 || echo "")
                
                if echo "$ERROR" | grep -qi "insufficient\|unavailable"; then
                    echo "    ❌ Instance type unavailable in $region"
                    continue
                elif echo "$ERROR" | grep -qi "limit\|quota"; then
                    echo "    ❌ Quota/limit issue - skipping this instance type"
                    break
                elif echo "$ERROR" | grep -qi "key.*not found"; then
                    echo "    ❌ Key pair '$KEY_NAME' not found in $region"
                    echo "    Attempting to create key pair..."
                    KEY_OUTPUT=$(aws ec2 create-key-pair \
                        --region $region \
                        --key-name $KEY_NAME \
                        --query 'KeyMaterial' \
                        --output text 2>&1)
                    
                    if echo "$KEY_OUTPUT" | grep -q "BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY"; then
                        echo "$KEY_OUTPUT" > ~/.ssh/$KEY_NAME.pem
                        chmod 400 ~/.ssh/$KEY_NAME.pem
                        echo "    ✓ Key pair created and saved to ~/.ssh/$KEY_NAME.pem"
                        # Retry instance creation
                        continue
                    else
                        echo "    ❌ Failed to create key pair: $KEY_OUTPUT"
                        continue
                    fi
                else
                    echo "    ❌ Failed: $ERROR"
                    continue
                fi
            fi
        done
        
        # Small delay between different instance types
        if [ "$SUCCESS" = false ]; then
            sleep 2
        fi
    done
    
    # If we succeeded, break out of pricing loop
    if [ "$SUCCESS" = true ]; then
        break
    fi
    
    # If on-demand failed, try spot
    if [ "$SUCCESS" = false ] && [ "$instance_pricing" = "on-demand" ]; then
        echo ""
        echo "⚠️  On-demand instances failed. Trying spot instances (60-90% cheaper)..."
        echo ""
    fi
done

# Final result
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$SUCCESS" = true ]; then
    echo "✅ EC2 instance created successfully!"
    echo ""
    echo "📝 Instance Details:"
    echo "   Name: $INSTANCE_NAME"
    echo "   Instance ID: $CREATED_INSTANCE_ID"
    echo "   Region: $CREATED_REGION"
    echo "   Instance Type: $CREATED_INSTANCE_FAMILY"
    echo "   GPU: $CREATED_GPU"
    echo "   Pricing: $CREATED_INSTANCE_TYPE"
    if [ "$CREATED_INSTANCE_TYPE" = "spot" ]; then
        echo "   ⚠️  SPOT INSTANCE: Can be terminated by AWS"
        echo "   💰 Cost: 60-90% cheaper than on-demand"
    fi
    echo ""
    echo "🔗 View in AWS Console:"
    echo "   Direct link: https://console.aws.amazon.com/ec2/v2/home?region=$CREATED_REGION#Instances:instanceId=$CREATED_INSTANCE_ID"
    echo "   EC2 Dashboard: https://console.aws.amazon.com/ec2/v2/home?region=$CREATED_REGION#Instances:"
    echo ""
    
    # Wait for instance to be running
    echo "⏳ Waiting for instance to be running..."
    aws ec2 wait instance-running \
        --region $CREATED_REGION \
        --instance-ids $CREATED_INSTANCE_ID 2>/dev/null || true
    
    sleep 10  # Give it a bit more time to initialize
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region $CREATED_REGION \
        --instance-ids $CREATED_INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null || echo "Not assigned yet")
    
    echo ""
    echo "📝 Network Details:"
    echo "   Public IP: $PUBLIC_IP"
    echo ""
    echo "🔗 Connect via SSH:"
    echo "   ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
    echo "   (or ec2-user@$PUBLIC_IP for Amazon Linux)"
    echo ""
    
    # Update region in other scripts
    echo "💡 Updating region in management scripts..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for script in aws_start_instance.sh aws_stop_instance.sh aws_get_status.sh aws_delete_instance.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|REGION=\".*\"|REGION=\"$CREATED_REGION\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
                sed -i '' "s|INSTANCE_ID=\".*\"|INSTANCE_ID=\"$CREATED_INSTANCE_ID\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            else
                sed -i "s|REGION=\".*\"|REGION=\"$CREATED_REGION\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
                sed -i "s|INSTANCE_ID=\".*\"|INSTANCE_ID=\"$CREATED_INSTANCE_ID\"|g" "$SCRIPT_DIR/$script" 2>/dev/null || true
            fi
        fi
    done
    echo "   ✅ Region and Instance ID updated in management scripts"
    echo ""
    
    # Cost information
    echo "💰 Cost Information:"
    if [ "$CREATED_INSTANCE_TYPE" = "spot" ]; then
        echo "   - Spot instance: 60-90% cheaper"
        echo "   - Estimated: ~₹15-30/hour (~$0.18-0.36/hour)"
    else
        case "$CREATED_INSTANCE_FAMILY" in
            g4dn.xlarge)
                echo "   - g4dn.xlarge (T4): ~₹70-80/hour (~$0.85-0.95/hour)"
                ;;
            g4dn.2xlarge)
                echo "   - g4dn.2xlarge (T4): ~₹140-160/hour (~$1.70-1.90/hour)"
                ;;
            g5.xlarge)
                echo "   - g5.xlarge (A10G): ~₹150-180/hour (~$1.80-2.20/hour)"
                ;;
            g5.2xlarge)
                echo "   - g5.2xlarge (A10G): ~₹300-360/hour (~$3.60-4.40/hour)"
                ;;
            p3.2xlarge)
                echo "   - p3.2xlarge (V100): ~₹200-250/hour (~$2.40-3.00/hour)"
                ;;
        esac
    fi
    echo "   - EBS storage: ~₹10/month (~$0.12/month) for 30GB"
    echo "   - Stop instance when not in use: ./aws/aws_stop_instance.sh"
    echo "   - Start instance when needed: ./aws/aws_start_instance.sh"
    echo ""
    
    echo "📚 Next steps:"
    echo "   1. SSH into the instance: ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
    echo "   2. Clone your repository: git clone <your-repo-url> V2VBot"
    echo "   3. Setup and run: cd V2VBot && cp env.example .env && bash setup_server.sh"
    echo "   4. Or manually: python3 -m venv venv && source venv/bin/activate && pip install -r server/requirements.txt"
    echo "   5. Start server: python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080"
    echo ""
    
    if [ "$CREATED_INSTANCE_TYPE" = "spot" ]; then
        echo "⚠️  IMPORTANT: Spot instances can be terminated by AWS at any time."
        echo "   - Maximum runtime: Not guaranteed"
        echo "   - Not suitable for production workloads requiring high availability"
        echo "   - Great for development, testing, or cost-sensitive workloads"
        echo ""
    fi
    
else
    echo "❌ Failed to create instance after trying all configurations"
    echo ""
    echo "💡 Suggestions:"
    echo "   1. Create key pair first:"
      echo "      aws ec2 create-key-pair --region ap-south-2 --key-name $KEY_NAME --query 'KeyMaterial' --output text > ~/.ssh/$KEY_NAME.pem"
    echo "      chmod 400 ~/.ssh/$KEY_NAME.pem"
    echo "   2. Try again later (availability changes frequently)"
    echo "   3. Request service quota increase:"
    echo "      https://console.aws.amazon.com/servicequotas/home"
    echo "   4. Try creating manually from console:"
    echo "      https://console.aws.amazon.com/ec2/v2/home"
    echo ""
    echo "📊 What was tried:"
    echo "   - On-demand instances: g4dn, g5, p3 in multiple regions"
    echo "   - Spot instances: g4dn, g5, p3 in multiple regions"
    echo "   - Regions: Mumbai (India), Ireland (Europe), N. Virginia (US), Singapore"
    echo ""
    exit 1
fi

