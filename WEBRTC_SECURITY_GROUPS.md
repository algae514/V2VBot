# WebRTC Security Group Configuration Guide

## Problem: WebRTC Connection Issues on AWS

If your V2VBot app starts but WebRTC communication doesn't work, the issue is almost certainly with your **AWS Security Group** configuration.

### Why This Happens

WebRTC requires **two types of network traffic**:

1. **TCP Port 8080** (HTTPS/HTTP) - For signaling (SDP offer/answer exchange)
   - ✅ This is working (app starts, you can access the web page)
   - ✅ Your security group likely already allows this

2. **UDP Ports (10000-65535)** - For actual media transport (RTP/RTCP)
   - ❌ This is likely **blocked** by your security group
   - ❌ Without UDP, ICE candidates can't establish peer-to-peer connection
   - ❌ Result: Signaling works, but audio never flows

### WebRTC Port Requirements

WebRTC uses **dynamic UDP ports** for media streams. The exact ports are negotiated during ICE (Interactive Connectivity Establishment), but they typically fall in these ranges:

- **Recommended**: UDP ports **10000-65535** (entire ephemeral range)
- **Minimum**: UDP ports **49152-65535** (IANA ephemeral port range)
- **STUN**: UDP port **19302** (for `stun.l.google.com:19302`)

### Solution: Update AWS Security Group

**🚀 Quick Method: Run from Server (Recommended)**

If you're on the EC2 instance, you can configure security groups automatically:

```bash
cd /home/ubuntu/V2VBot
./setup_security_groups.sh
```

This script will:
- ✅ Automatically detect your instance and security group
- ✅ Install AWS CLI if needed
- ✅ Add UDP ports 10000-65535 (WebRTC media)
- ✅ Add UDP port 19302 (STUN server)
- ✅ Verify/add TCP port 8080 (signaling)

**Requirements:**
- Instance must have an IAM role with `ec2:AuthorizeSecurityGroupIngress` permission
- OR configure AWS credentials: `aws configure`

---

**Manual Method: AWS Console**

#### Step 1: Identify Your Security Group

1. Go to **EC2 Console** → **Instances**
2. Select your instance
3. Click **Security** tab
4. Note the **Security Group** name(s)

#### Step 2: Add UDP Rules

1. Go to **EC2 Console** → **Security Groups**
2. Select your security group
3. Click **Edit inbound rules**
4. Click **Add rule**

**Add these rules:**

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 10000-65535 | 0.0.0.0/0 | WebRTC Media (RTP/RTCP) |
| Custom UDP | UDP | 19302 | 0.0.0.0/0 | STUN Server |

**OR** (more restrictive, if you want to limit access):

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 10000-65535 | Your IP/32 | WebRTC Media (RTP/RTCP) |
| Custom UDP | UDP | 19302 | 0.0.0.0/0 | STUN Server |

**Note**: For production, consider restricting source IPs instead of `0.0.0.0/0`.

#### Step 3: Verify TCP Port 8080

Make sure you also have:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 8080 | 0.0.0.0/0 | HTTPS/HTTP Signaling |

#### Step 4: Save and Test

1. Click **Save rules**
2. Wait 10-30 seconds for changes to propagate
3. Refresh your browser and try connecting again
4. Check browser console (F12) for WebRTC connection state

### Complete Security Group Configuration

Here's what your security group should look like:

**Inbound Rules:**
```
Type          Protocol    Port Range      Source          Description
---------------------------------------------------------------------------
SSH           TCP         22              Your IP/32      SSH Access
HTTPS         TCP         443             0.0.0.0/0       HTTPS (if using)
Custom TCP    TCP         8080            0.0.0.0/0       WebRTC Signaling
Custom UDP    UDP         10000-65535     0.0.0.0/0       WebRTC Media
Custom UDP    UDP         19302           0.0.0.0/0       STUN Server
```

### Alternative: Using AWS CLI Manually

If you prefer to run commands manually:

```bash
# Get your instance ID and region
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')

# Get your security group ID
SG_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

# Add UDP rule for WebRTC media (10000-65535)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --region $REGION \
  --ip-permissions "IpProtocol=udp,FromPort=10000,ToPort=65535,IpRanges=[{CidrIp=0.0.0.0/0,Description='WebRTC Media (RTP/RTCP)'}]"

# Add UDP rule for STUN
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --region $REGION \
  --ip-permissions "IpProtocol=udp,FromPort=19302,ToPort=19302,IpRanges=[{CidrIp=0.0.0.0/0,Description='STUN Server'}]"
```

**Note:** The automated script (`setup_security_groups.sh`) does all of this for you!

### Verification

After updating security groups, check WebRTC connection in browser console:

1. Open browser DevTools (F12)
2. Go to **Console** tab
3. Look for WebRTC logs:
   - `ice candidate` - Should show candidates being generated
   - `ice gathering` - Should progress: `gathering` → `complete`
   - `ice state` - Should progress: `new` → `checking` → `connected`
   - `pc state` - Should progress: `new` → `connecting` → `connected`

**If you see:**
- `ice state: failed` or `disconnected` → UDP ports still blocked
- `ice state: checking` (stuck) → UDP ports blocked or NAT traversal failing
- `ice state: connected` → ✅ Success! Security groups are correct

### Troubleshooting

#### Still Not Working?

1. **Check IAM permissions:**
   ```bash
   # If script failed, check if instance has IAM role with permissions
   # Required permission: ec2:AuthorizeSecurityGroupIngress
   # Or configure AWS credentials manually:
   aws configure
   ```

2. **Check firewall on instance:**
   ```bash
   sudo ufw status
   sudo ufw allow 10000:65535/udp
   sudo ufw allow 19302/udp
   ```

3. **Verify ports are open:**
   ```bash
   # From your local machine, test UDP port
   nc -u -v your-server-ip 50000
   ```

4. **Check WebRTC logs in server:**
   ```bash
   tail -f logs/server.log | grep -i "ice\|connection"
   ```

5. **Browser console errors:**
   - Look for `RTCPeerConnection` errors
   - Check Network tab for failed WebRTC connections

#### Using TURN Server (Advanced)

If you're behind a restrictive NAT/firewall, you may need a TURN server:

1. Set up a TURN server (e.g., coturn)
2. Update `web/src/main.js`:
   ```javascript
   iceServers: [
     { urls: 'stun:stun.l.google.com:19302' },
     { 
       urls: 'turn:your-turn-server.com:3478',
       username: 'your-username',
       credential: 'your-password'
     }
   ]
   ```

### Security Considerations

**For Production:**

1. **Restrict UDP source IPs** if possible (if users have static IPs)
2. **Use a TURN server** behind a firewall instead of opening all UDP ports
3. **Monitor security group logs** for suspicious traffic
4. **Consider using AWS WAF** for additional protection

**For Development:**

- Opening UDP 10000-65535 from `0.0.0.0/0` is acceptable for testing
- Always use HTTPS (port 8080 with SSL) in production

### Summary

**The Fix:**
1. ✅ Add UDP port range **10000-65535** to your security group
2. ✅ Add UDP port **19302** for STUN
3. ✅ Verify TCP port **8080** is open
4. ✅ Wait for changes to propagate
5. ✅ Test WebRTC connection

**Why it works:**
- TCP 8080 = Signaling (SDP exchange) ✅
- UDP 10000-65535 = Media transport (RTP/RTCP) ✅
- UDP 19302 = STUN (NAT traversal) ✅

Without UDP ports, WebRTC can't establish the peer-to-peer media connection, even though the signaling (HTTP) works fine.
