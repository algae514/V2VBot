# GCP Deployment Guide for V2VBot

This guide covers deploying V2VBot on Google Cloud Platform (GCP) with a minimal GPU VM instance optimized for cost savings.

## Overview

This setup creates a cost-effective GPU-enabled VM that you can start/stop on-demand to minimize costs when not in use.

## Prerequisites

1. **GCP Account**: Google Cloud Platform account with billing enabled
2. **Project**: V2VBot project created in GCP Console
3. **Billing**: Billing account linked to the project
4. **GCP CLI**: Google Cloud SDK installed (see setup script)

## Quick Start

### Step 1: Install and Setup GCP CLI

```bash
# Run the setup script
./gcp/gcp_setup.sh
```

This script will:
- Check/install gcloud CLI
- Initialize authentication
- Set project to V2VBot
- Enable required APIs

### Step 2: Create VM Instance

```bash
# Create the GPU VM instance
./gcp/gcp_create_vm.sh
```

This creates:
- **Instance**: `v2vbot-vm`
- **Region**: `asia-south1` (Mumbai, India)
- **Zone**: `asia-south1-a` (T4 GPU available)
- **Machine Type**: `n1-standard-2` (2 vCPU, 7.5GB RAM)
- **GPU**: NVIDIA Tesla T4 (1x)
- **Disk**: 30GB standard persistent disk
- **OS**: Ubuntu 22.04 LTS
- **Auto-installs**: NVIDIA drivers, CUDA, Docker, NVIDIA Container Toolkit

**Note**: First-time creation takes 5-10 minutes for driver installation.

### Step 3: Start/Stop VM (Cost Management)

```bash
# Start VM when you need it
./gcp/gcp_start_vm.sh

# Stop VM when done (saves compute costs)
./gcp/gcp_stop_vm.sh

# Check VM status
./gcp/gcp_get_status.sh
```

## Cost Optimization

### Cost Breakdown (India Region - Mumbai)

**When Running:**
- **Machine (n1-standard-2)**: ~₹45/hour (~$0.55/hour)
  - 2 vCPU × ₹22.5/vCPU/hour = ₹45/hour
  - 7.5GB RAM × ₹2.5/GB/hour = ₹18.75/hour
  - Total machine: ~₹45/hour
- **GPU (NVIDIA T4)**: ~₹28/hour (~$0.35/hour)
- **Total Compute + GPU**: ~₹73/hour (~$0.90/hour)
- **Disk**: ~₹15/month (~$0.18/month) for 30GB standard disk

**When Stopped:**
- **Compute**: ₹0/hour (no charges)
- **GPU**: ₹0/hour (no charges)
- **Disk**: ~₹15/month (~$0.18/month) for storage only

### Best Practices

1. **Stop VM When Not in Use**: Always run `./gcp/gcp_stop_vm.sh` when done
2. **Use On-Demand**: Start only when needed (1-2 hours at a time)
3. **Monitor Usage**: Check GCP Console billing dashboard regularly
4. **Set Budget Alerts**: Configure billing alerts in GCP Console

### Estimated Monthly Cost (India Region)

**Scenario 1: Light Usage (1 hour/day, 30 days)**
- Compute: 30 hours × ₹73/hour = ₹2,190 (~$27/month)
- Disk: ₹15/month
- **Total: ~₹2,205/month (~$27/month)**

**Scenario 2: Moderate Usage (2 hours/day, 30 days)**
- Compute: 60 hours × ₹73/hour = ₹4,380 (~$54/month)
- Disk: ₹15/month
- **Total: ~₹4,395/month (~$54/month)**

**Scenario 3: Heavy Usage (4 hours/day, 30 days)**
- Compute: 120 hours × ₹73/hour = ₹8,760 (~$108/month)
- Disk: ₹15/month
- **Total: ~₹8,775/month (~$108/month)**

**Note**: Costs scale proportionally with usage. You only pay when the VM is running!

## Deployment Steps

### 1. Connect to VM

```bash
# SSH into the instance
gcloud compute ssh v2vbot-vm --zone=asia-south1-a
```

### 2. Clone Repository

```bash
# On the VM
cd /home
git clone <your-repo-url> V2VBot
cd V2VBot
```

### 3. Configure Environment

```bash
# Copy environment template
cp env.example .env

# Edit environment file
nano .env
# Add your GEMINI_API_KEY
```

### 4. Deploy Application

The VM is pre-configured with all system dependencies. Just clone and run:

```bash
# Clone your repository
cd /home
git clone <your-repo-url> V2VBot
cd V2VBot

# Copy environment template
cp env.example .env
nano .env  # Add your GEMINI_API_KEY

# Create virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r server/requirements.txt

# Start the server
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

**Or use the setup script (if available):**
```bash
bash setup_server.sh  # This will set up everything automatically
```

### 5. Configure Firewall

```bash
# Allow HTTP traffic on port 8080
gcloud compute firewall-rules create allow-v2vbot-http \
    --allow tcp:8080 \
    --source-ranges 0.0.0.0/0 \
    --description "Allow HTTP traffic for V2VBot"
```

### 6. Access Application

Get the external IP:
```bash
gcloud compute instances describe v2vbot-vm --zone=asia-south1-a \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

Access at: `http://<EXTERNAL_IP>:8080`

## VM Management Scripts

All scripts are in the project root:

| Script | Purpose |
|--------|---------|
| `gcp/gcp_setup.sh` | Initial GCP setup and authentication |
| `gcp/gcp_create_vm.sh` | Create the GPU VM instance |
| `gcp/gcp_start_vm.sh` | Start the VM instance |
| `gcp/gcp_stop_vm.sh` | Stop the VM (saves costs) |
| `gcp/gcp_get_status.sh` | Check VM status and details |
| `gcp/gcp_delete_vm.sh` | Delete VM (removes all data) |

## Configuration

### Change Zone/Region

Edit the scripts and change:
```bash
ZONE="asia-south1-a"  # Mumbai, India (T4 GPU available in zones a and b)
REGION="asia-south1"  # Mumbai, India region
```

**Available Zones in India (Mumbai):**
- `asia-south1-a`: NVIDIA T4 GPUs available
- `asia-south1-b`: NVIDIA T4 GPUs available
- `asia-south1-c`: NVIDIA H100 GPUs available (more expensive)

### Change Machine Type

Edit `gcp/gcp_create_vm.sh`:
```bash
MACHINE_TYPE="n1-standard-2"  # Options: n1-standard-1, n1-standard-2, etc.
```

### Change GPU Type

Edit `gcp/gcp_create_vm.sh`:
```bash
GPU_TYPE="nvidia-tesla-t4"  # Options: nvidia-tesla-t4, nvidia-tesla-v100, etc.
```

**Note**: Different GPU types have different costs and availability per zone.

## Verification

After deployment, verify GPU is working:

```bash
# SSH into VM
gcloud compute ssh v2vbot-vm --zone=asia-south1-a

# Check GPU
nvidia-smi

# Check CUDA
python3 -c "import torch; print(torch.cuda.is_available())"
```

Expected output:
```
✓ GPU detected: NVIDIA Tesla T4
✓ CUDA available: True
```

## Troubleshooting

### GPU Not Available

1. **Check Quota**: Visit [GCP Quotas](https://console.cloud.google.com/iam-admin/quotas)
2. **Request Increase**: Request GPU quota for your region
3. **Try Different Zone**: Some zones have better GPU availability

### Instance Won't Start

1. **Check Status**: `./gcp/gcp_get_status.sh`
2. **Check Logs**: GCP Console → Compute Engine → VM instances → View logs
3. **Check Billing**: Ensure billing is enabled and active

### High Costs

1. **Stop VM**: Always run `./gcp/gcp_stop_vm.sh` when done
2. **Check Usage**: Review GCP Console billing dashboard
3. **Set Budget Alerts**: Configure alerts in GCP Console

### Connection Issues

1. **Check Firewall**: Ensure port 8080 is open
2. **Check External IP**: Verify IP with `./gcp/gcp_get_status.sh`
3. **Check Service**: SSH into VM and check if service is running

## Advanced: Preemptible Instances (Optional)

For even lower costs, you can use preemptible instances (up to 80% discount):

**Warning**: Preemptible instances can be terminated by GCP at any time.

To create a preemptible instance, modify `gcp/gcp_create_vm.sh` and add:
```bash
--preemptible
```

## Security Best Practices

1. **Use SSH Keys**: Use gcloud SSH instead of password authentication
2. **Restrict Firewall**: Only open necessary ports
3. **Use IAM**: Create service accounts with minimal permissions
4. **Enable Logging**: Monitor access and usage logs

## Next Steps

1. **Deploy Application**: Follow deployment steps above
2. **Test Functionality**: Verify voice-to-voice pipeline works
3. **Monitor Costs**: Set up billing alerts
4. **Optimize Usage**: Start/stop VM based on actual usage patterns

## Additional Resources

- [GCP Compute Engine Pricing](https://cloud.google.com/compute/pricing)
- [GCP GPU Pricing](https://cloud.google.com/compute/gpus-pricing)
- [GCP Documentation](https://cloud.google.com/docs)
- [GCP Billing Dashboard](https://console.cloud.google.com/billing)

