#!/bin/bash
# Script to automatically configure AWS Security Groups for WebRTC
# This script runs from the EC2 instance and configures its own security group

set -euo pipefail

echo "==================================="
echo "WebRTC Security Group Configuration"
echo "==================================="
echo ""

# Check if running on AWS EC2
if ! curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id > /dev/null 2>&1; then
    echo "❌ Error: This script must be run on an AWS EC2 instance"
    echo "   The instance metadata service is not accessible."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "⚠️  AWS CLI not found. Installing..."
    
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update -qq
        sudo apt-get install -y awscli
    elif command -v yum &> /dev/null; then
        # Amazon Linux / CentOS / RHEL
        sudo yum install -y aws-cli
    else
        echo "❌ Error: Cannot install AWS CLI automatically"
        echo "   Please install AWS CLI manually:"
        echo "   https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
fi

# Verify AWS CLI is working
if ! aws --version &> /dev/null; then
    echo "❌ Error: AWS CLI installation failed"
    exit 1
fi

echo "✓ AWS CLI is available"
echo ""

# Get instance metadata
echo "Fetching instance information..."
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "N/A")

echo "  Instance ID: $INSTANCE_ID"
echo "  Region: $REGION"
echo "  Public IP: $PUBLIC_IP"
echo ""

# Get security group ID(s)
echo "Getting security group information..."
SG_IDS=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
    --output text 2>/dev/null)

if [ -z "$SG_IDS" ] || [ "$SG_IDS" == "None" ]; then
    echo "❌ Error: Could not retrieve security group information"
    echo "   Make sure the instance has an IAM role with EC2 permissions, or"
    echo "   configure AWS credentials manually:"
    echo "   aws configure"
    exit 1
fi

echo "  Found security group(s): $SG_IDS"
echo ""

# Function to check if a rule already exists
check_rule_exists() {
    local sg_id=$1
    local protocol=$2
    local port_range=$3
    local cidr=$4
    
    aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$REGION" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='$protocol' && FromPort==\`$port_range\` && ToPort==\`$port_range\` && IpRanges[?CidrIp=='$cidr']]" \
        --output text 2>/dev/null | grep -q "$cidr" && return 0 || return 1
}

# Function to add security group rule
add_security_group_rule() {
    local sg_id=$1
    local protocol=$2
    local port_range=$3
    local description=$4
    local cidr="${5:-0.0.0.0/0}"
    
    # Parse port range (e.g., "10000-65535" or "19302")
    if [[ "$port_range" == *"-"* ]]; then
        FROM_PORT=$(echo "$port_range" | cut -d'-' -f1)
        TO_PORT=$(echo "$port_range" | cut -d'-' -f2)
    else
        FROM_PORT="$port_range"
        TO_PORT="$port_range"
    fi
    
    # Check if rule already exists
    if check_rule_exists "$sg_id" "$protocol" "$FROM_PORT" "$cidr"; then
        echo "  ⚠️  Rule already exists: $protocol $port_range from $cidr"
        return 0
    fi
    
    echo "  Adding rule: $protocol $port_range from $cidr ($description)"
    
    if aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --ip-permissions "IpProtocol=$protocol,FromPort=$FROM_PORT,ToPort=$TO_PORT,IpRanges=[{CidrIp=$cidr,Description='$description'}]" \
        --region "$REGION" \
        --output text 2>/dev/null; then
        echo "  ✓ Rule added successfully"
        return 0
    else
        echo "  ❌ Failed to add rule (may already exist or insufficient permissions)"
        return 1
    fi
}

# Process each security group
SUCCESS_COUNT=0
FAILED_COUNT=0

for SG_ID in $SG_IDS; do
    echo "Configuring security group: $SG_ID"
    echo "-----------------------------------"
    
    # Add UDP rule for WebRTC media (10000-65535)
    if add_security_group_rule "$SG_ID" "udp" "10000-65535" "WebRTC Media (RTP/RTCP)"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
    fi
    
    # Add UDP rule for STUN server
    if add_security_group_rule "$SG_ID" "udp" "19302" "STUN Server"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILED_COUNT++))
    fi
    
    # Verify TCP 8080 exists (for signaling)
    echo "  Checking TCP port 8080 (signaling)..."
    if check_rule_exists "$SG_ID" "tcp" "8080" "0.0.0.0/0"; then
        echo "  ✓ TCP 8080 already configured"
    else
        echo "  ⚠️  TCP 8080 not found - adding..."
        if add_security_group_rule "$SG_ID" "tcp" "8080" "WebRTC Signaling (HTTPS/HTTP)"; then
            ((SUCCESS_COUNT++))
        else
            ((FAILED_COUNT++))
        fi
    fi
    
    echo ""
done

# Summary
echo "==================================="
echo "Configuration Summary"
echo "==================================="
echo "  Rules added/verified: $SUCCESS_COUNT"
if [ $FAILED_COUNT -gt 0 ]; then
    echo "  Failed: $FAILED_COUNT"
fi
echo ""

# Wait for changes to propagate
echo "Waiting 10 seconds for changes to propagate..."
sleep 10

echo ""
echo "✅ Security group configuration complete!"
echo ""
echo "Your WebRTC application should now work properly."
echo ""
echo "To verify, check your browser console (F12) when connecting:"
echo "  - Look for 'ice state: connected' (success)"
echo "  - If you see 'ice state: failed', wait a bit longer and try again"
echo ""
echo "If you still have issues:"
echo "  1. Check IAM role permissions (needs ec2:AuthorizeSecurityGroupIngress)"
echo "  2. Verify security group rules in AWS Console"
echo "  3. Check firewall on instance: sudo ufw status"
echo ""
