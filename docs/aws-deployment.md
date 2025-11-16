# AWS EC2 Deployment Guide for V2VBot

This guide covers deploying V2VBot on AWS EC2 with GPU instances, similar to the GCP setup.

## Overview

This setup creates a cost-effective GPU-enabled EC2 instance that you can start/stop on-demand to minimize costs when not in use.

## Prerequisites

1. **AWS Account**: AWS account with billing enabled
2. **AWS CLI**: AWS Command Line Interface installed
3. **Access Keys**: AWS Access Key ID and Secret Access Key
4. **Key Pair**: EC2 Key Pair for SSH access (will be created if needed)

## Quick Start

### Step 1: Install and Setup AWS CLI

```bash
# Run the setup script
./aws/aws_setup.sh
```

This script will:
- Check/install AWS CLI
- Configure authentication
- Set default region

### Step 2: Create EC2 Instance

```bash
# Create the GPU EC2 instance
./aws/aws_create_instance.sh
```

This creates:
- **Instance**: `v2vbot-vm`
- **Instance Types**: g4dn.xlarge (T4), g5.xlarge (A10G), or p3.2xlarge (V100)
- **GPU**: NVIDIA T4, A10G, or V100 (depending on availability)
- **Disk**: 30GB gp3 EBS volume
- **OS**: Ubuntu 22.04 LTS
- **Auto-installs**: NVIDIA drivers, CUDA, system dependencies

**Note**: The script tries multiple regions, instance types, and spot instances to find availability.

### Step 3: Start/Stop Instance (Cost Management)

```bash
# Start instance when you need it
./aws/aws_start_instance.sh

# Stop instance when done (saves compute costs)
./aws/aws_stop_instance.sh

# Check instance status
./aws/aws_get_status.sh
```

## Cost Optimization

### Cost Breakdown (India Region - Mumbai)

**When Running (ap-south-2 - Hyderabad, India):**
- **g4dn.xlarge (T4)**: ~₹70-80/hour (~$0.85-0.95/hour)
- **g4dn.2xlarge (T4)**: ~₹140-160/hour (~$1.70-1.90/hour)
- **g5.xlarge (A10G)**: ~₹150-180/hour (~$1.80-2.20/hour)
- **Spot Instances**: 60-90% cheaper (60-90% discount)

**When Stopped:**
- **Compute**: ₹0/hour (no charges)
- **EBS Storage**: ~₹10/month (~$0.12/month) for 30GB

### Estimated Monthly Cost

**Scenario 1: Light Usage (1 hour/day, 30 days)**
- Compute: 30 hours × ₹75/hour = ₹2,250 (~$27/month)
- EBS: ₹10/month
- **Total: ~₹2,260/month (~$27/month)**

**Scenario 2: Moderate Usage (2 hours/day, 30 days)**
- Compute: 60 hours × ₹75/hour = ₹4,500 (~$54/month)
- EBS: ₹10/month
- **Total: ~₹4,510/month (~$54/month)**

**Note**: Costs scale proportionally with usage. You only pay when the instance is running!

## Instance Types

The script tries these instance types in order:

1. **g4dn.xlarge** - NVIDIA T4 GPU, 4 vCPU, 16GB RAM (most cost-effective)
2. **g4dn.2xlarge** - NVIDIA T4 GPU, 8 vCPU, 32GB RAM
3. **g5.xlarge** - NVIDIA A10G GPU, 4 vCPU, 16GB RAM (more powerful)
4. **g5.2xlarge** - NVIDIA A10G GPU, 8 vCPU, 32GB RAM
5. **p3.2xlarge** - NVIDIA V100 GPU, 8 vCPU, 61GB RAM

## Regions

The script tries these regions in order:
- **ap-south-2** (Hyderabad, India) - Primary
- **ap-south-1** (Mumbai, India) - Fallback
- **eu-west-1** (Ireland, Europe)
- **us-east-1** (N. Virginia, US)
- **ap-southeast-1** (Singapore)

## Deployment Steps

### 1. Import Key Pair to All Regions (One-Time)

**If you already have a key pair** (`~/.ssh/v2vbot-key.pem`), import it to all regions:

```bash
./aws/aws_account_setup.sh
```

This imports your existing key pair to all AWS regions automatically.

**If you don't have a key pair yet:**
```bash
# Create key pair in one region
aws ec2 create-key-pair \
    --region ap-south-2 \
    --key-name v2vbot-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/v2vbot-key.pem

# Set permissions
chmod 400 ~/.ssh/v2vbot-key.pem

# Then import to all regions
./aws/aws_account_setup.sh
```

**Note:** This is a one-time setup. The key pair will be reused for all future instances.

### 2. Connect to Instance

```bash
# SSH into the instance
ssh -i ~/.ssh/v2vbot-key.pem ubuntu@<PUBLIC_IP>
```

### 3. Deploy Application

```bash
# Clone your repository
cd /home
git clone <your-repo-url> V2VBot
cd V2VBot

# Copy environment template
cp env.example .env

# Edit environment file
nano .env
# Add your GEMINI_API_KEY

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r server/requirements.txt

# Start the server
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

### 4. Access Application

Get the public IP from the instance details and access:
```
http://<PUBLIC_IP>:8080
```

## VM Management Scripts

All scripts are in the `aws/` folder:

| Script | Purpose |
|--------|---------|
| `aws/aws_setup.sh` | Initial AWS setup and authentication |
| `aws/aws_create_instance.sh` | Create the GPU EC2 instance (robust, tries multiple options) |
| `aws/aws_start_instance.sh` | Start the instance |
| `aws/aws_stop_instance.sh` | Stop the instance (saves costs) |
| `aws/aws_get_status.sh` | Check instance status and details |
| `aws/aws_delete_instance.sh` | Delete instance (removes all data) |

## Configuration

### Change Region

Edit the scripts and change:
```bash
REGION="ap-south-2"  # Change to your preferred region (default: Hyderabad, India)
```

### Change Instance Type

Edit `aws/aws_create_instance.sh` and modify the `INSTANCE_CONFIGS` array.

### Change Key Pair Name

Edit `aws/aws_create_instance.sh`:
```bash
KEY_NAME="v2vbot-key"  # Change to your key pair name
```

## Verification

After deployment, verify GPU is working:

```bash
# SSH into instance
ssh -i ~/.ssh/v2vbot-key.pem ubuntu@<PUBLIC_IP>

# Check GPU
nvidia-smi

# Check CUDA
python3 -c "import torch; print(torch.cuda.is_available())"
```

Expected output:
```
✓ GPU detected: NVIDIA T4 (or A10G/V100)
✓ CUDA available: True
```

## Troubleshooting

### Instance Creation Fails

1. **Check Key Pair**: Ensure key pair exists in the region
2. **Check Quotas**: Visit [AWS Service Quotas](https://console.aws.amazon.com/servicequotas)
3. **Try Different Region**: Some regions have better availability
4. **Try Spot Instances**: Script automatically tries spot if on-demand fails

### GPU Not Detected

1. **Wait for Drivers**: GPU drivers install on first boot (5-10 minutes)
2. **Check Logs**: `sudo journalctl -u cloud-init`
3. **Verify Instance Type**: Ensure instance type has GPU

### Can't Access Application

1. **Check Security Group**: Ensure port 8080 is open
2. **Check Public IP**: Verify instance has public IP
3. **Check Service**: SSH and verify server is running

### High Costs

1. **Stop Instance**: Always run `./aws/aws_stop_instance.sh` when done
2. **Use Spot Instances**: 60-90% cheaper (script tries automatically)
3. **Check Usage**: Review AWS Cost Explorer

## Comparison: AWS vs GCP

| Feature | AWS EC2 | GCP Compute Engine |
|---------|---------|-------------------|
| **GPU Types** | T4, A10G, V100 | T4, A10, A100 |
| **Cost (T4)** | ~₹75/hour | ~₹73/hour |
| **Availability** | Generally better | Can be limited |
| **Spot/Preemptible** | 60-90% discount | 60-90% discount |
| **Regions** | More regions | Fewer regions |

## Next Steps

1. **Deploy Application**: Follow deployment steps above
2. **Test Functionality**: Verify voice-to-voice pipeline works
3. **Monitor Costs**: Set up AWS Cost Alerts
4. **Optimize Usage**: Start/stop instance based on actual usage patterns

## Additional Resources

- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [AWS GPU Instances](https://aws.amazon.com/ec2/instance-types/)
- [AWS Documentation](https://docs.aws.amazon.com/)
- [AWS Cost Calculator](https://calculator.aws/)

