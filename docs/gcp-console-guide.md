# GCP Console - Step-by-Step VM Creation Guide

This guide walks you through creating a GPU VM instance using the GCP Console (web interface).

## Prerequisites

1. **GCP Account** with billing enabled
2. **Project**: v2vbot (or your project)
3. **GPU Quota**: At least 1 GPU quota allocated
   - Check: https://console.cloud.google.com/iam-admin/quotas?project=v2vbot
   - Request if needed: Filter by "GPUS_ALL_REGIONS" and request quota increase

## Step-by-Step: Create GPU VM from Console

### Step 1: Navigate to Compute Engine

1. Go to [GCP Console](https://console.cloud.google.com)
2. Select your project: **v2vbot** (top dropdown)
3. Navigate to **Compute Engine** → **VM instances**
   - Direct link: https://console.cloud.google.com/compute/instances?project=v2vbot

### Step 2: Create New Instance

1. Click **"CREATE INSTANCE"** button (top of the page)

### Step 3: Configure Basic Settings

**Name:**
- Enter: `v2vbot-vm`

**Region and Zone:**
- **Region**: Select `europe-west4` (Netherlands) or `asia-south1` (Mumbai, India)
- **Zone**: Select `europe-west4-a` (or try `-b`, `-c` if `-a` unavailable)
  - **Tip**: Try different zones if you get "resource exhausted" errors

### Step 4: Configure Machine Type

**Machine family:**
- Select: **General-purpose**

**Machine type:**
- Select: **n1-standard-2**
  - 2 vCPU, 7.5 GB memory
  - (You can also try n1-standard-1 or n1-standard-4 if needed)

### Step 5: Configure GPU

1. Click **"GPU"** section to expand
2. **GPU type**: Select **NVIDIA Tesla T4**
3. **Number of GPUs**: Select **1**
4. **GPU availability**: 
   - If you see "Not available in this zone", try a different zone
   - Common available zones: `europe-west4-a`, `europe-west4-b`, `europe-west4-c`

### Step 6: Configure Boot Disk

1. Click **"Boot disk"** → **"CHANGE"**
2. **Operating system**: Select **Ubuntu**
3. **Version**: Select **Ubuntu 22.04 LTS**
4. **Boot disk type**: Select **Standard persistent disk**
5. **Size (GB)**: Enter **30** (or more if needed)
6. Click **"SELECT"**

### Step 7: Configure Firewall (Optional but Recommended)

1. Expand **"Networking, disks, security, management, sole tenancy"**
2. Click **"Networking"** tab
3. Under **"Network tags"**: Add tag `v2vbot-server`
4. Under **"Firewall"**: 
   - Check **"Allow HTTP traffic"**
   - Check **"Allow HTTPS traffic"**

### Step 8: Add Startup Script

1. Still in expanded settings, click **"Management"** tab
2. Scroll to **"Startup script"**
3. Paste this script:

```bash
#!/bin/bash
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
```

### Step 9: Review and Create

1. Review all settings:
   - Name: `v2vbot-vm`
   - Zone: `europe-west4-a` (or your chosen zone)
   - Machine: `n1-standard-2`
   - GPU: `1x NVIDIA Tesla T4`
   - Boot disk: `30GB Ubuntu 22.04 LTS`
   - Startup script: ✅ Added

2. Click **"CREATE"** button

### Step 10: Wait for Instance Creation

- **Status**: Instance will show "Creating..." then "Running"
- **Time**: Takes 2-5 minutes for VM, then 5-10 minutes for GPU drivers to install
- **Monitor**: Watch the status in the VM instances list

### Step 11: Configure Firewall Rule (If Not Done in Step 7)

1. Go to **VPC network** → **Firewall**
   - Direct link: https://console.cloud.google.com/networking/firewalls/list?project=v2vbot
2. Click **"CREATE FIREWALL RULE"**
3. **Name**: `allow-v2vbot-http`
4. **Direction**: Ingress
5. **Targets**: Specified target tags
6. **Target tags**: `v2vbot-server`
7. **Source IP ranges**: `0.0.0.0/0`
8. **Protocols and ports**: 
   - Check **TCP**
   - Enter **8080**
9. Click **"CREATE"**

### Step 12: Get External IP

1. Go back to **VM instances**
2. Find your instance `v2vbot-vm`
3. Copy the **External IP** address

### Step 13: SSH into Instance

**Option A: Using Console (Easiest)**
1. In VM instances list, click **"SSH"** button next to your instance
2. Browser-based SSH terminal will open

**Option B: Using gcloud CLI**
```bash
gcloud compute ssh v2vbot-vm --zone=europe-west4-a
```

### Step 14: Deploy Your Application

Once SSH'd into the instance:

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

### Step 15: Access Your Application

1. Get the **External IP** from VM instances list
2. Access: `http://<EXTERNAL_IP>:8080`
3. Open in browser to test

## Troubleshooting

### "Resource Exhausted" Error

**Solution:**
1. Try different zones in the same region (e.g., `europe-west4-b`, `europe-west4-c`)
2. Try different regions (e.g., `us-central1-a`, `europe-west1-a`)
3. Try again later (availability changes frequently)
4. Try different machine type (n1-standard-1 or n1-standard-4)

### "Quota Exceeded" Error

**Solution:**
1. Go to: https://console.cloud.google.com/iam-admin/quotas?project=v2vbot
2. Filter by "GPUS_ALL_REGIONS"
3. Request quota increase
4. Wait for approval (usually a few hours)

### GPU Not Detected

**Solution:**
1. Wait 5-10 minutes after VM creation (drivers installing)
2. SSH into instance
3. Check: `nvidia-smi`
4. If not working, check startup script logs:
   ```bash
   sudo journalctl -u google-startup-scripts.service
   ```

### Can't Access Application

**Solution:**
1. Check firewall rule is created (Step 11)
2. Verify port 8080 is open
3. Check if server is running: `ps aux | grep uvicorn`
4. Check server logs for errors

## Cost Management

### Stop VM When Not in Use

1. Go to VM instances list
2. Select your instance
3. Click **"STOP"** button
4. **Cost**: Only disk storage (~₹15/month) when stopped

### Start VM When Needed

1. Go to VM instances list
2. Select your stopped instance
3. Click **"START"** button
4. Wait 1-2 minutes for startup

### Delete VM (Permanent)

1. Go to VM instances list
2. Select your instance
3. Click **"DELETE"** button
4. **Warning**: This deletes all data!

## Quick Reference Links

- **VM Instances**: https://console.cloud.google.com/compute/instances?project=v2vbot
- **Quotas**: https://console.cloud.google.com/iam-admin/quotas?project=v2vbot
- **Firewall Rules**: https://console.cloud.google.com/networking/firewalls/list?project=v2vbot
- **Billing**: https://console.cloud.google.com/billing?project=v2vbot

## Next Steps

After VM is created and running:
1. Deploy your application (Step 14)
2. Set up monitoring and logging
3. Configure auto-start on boot (systemd service)
4. Set up regular backups
5. Monitor costs and usage

See [gcp-deployment.md](gcp-deployment.md) for detailed deployment instructions.

