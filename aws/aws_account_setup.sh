#!/bin/bash
# AWS Account Setup Script for V2VBot
# One-time setup: Import existing key pair to all AWS regions

set -e

KEY_NAME="v2vbot-key"
KEY_FILE="$HOME/.ssh/$KEY_NAME.pem"

# All regions we might use
REGIONS=(
    "ap-south-2"  # Hyderabad, India
    "ap-south-1"  # Mumbai, India
    "eu-west-1"    # Ireland, Europe
    "us-east-1"    # N. Virginia, US
    "ap-southeast-1" # Singapore
)

echo "🔑 Importing EC2 key pair to all AWS regions..."
echo "   Key name: $KEY_NAME"
echo ""

# Check AWS authentication
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS not authenticated. Run 'aws configure' first"
    exit 1
fi

# Check if key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ Key file not found: $KEY_FILE"
    echo ""
    echo "   Create the key pair first:"
    echo "   aws ec2 create-key-pair --region ap-south-2 --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_FILE"
    echo "   chmod 400 $KEY_FILE"
    echo ""
    exit 1
fi

# Extract public key
echo "Extracting public key from $KEY_FILE..."
PUBLIC_KEY=$(ssh-keygen -y -f "$KEY_FILE" 2>/dev/null || echo "")

if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ Failed to extract public key from $KEY_FILE"
    exit 1
fi

echo "✓ Public key extracted"
echo ""

# Import to all regions
echo "Importing key pair to all regions..."
echo ""

IMPORTED_COUNT=0
EXISTING_COUNT=0
FAILED_COUNT=0

for region in "${REGIONS[@]}"; do
    # Check if key already exists
    if aws ec2 describe-key-pairs --region $region --key-names $KEY_NAME &>/dev/null; then
        echo "  ✓ $region: Already exists"
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
        continue
    fi
    
    # Import key pair
    echo -n "  Importing to $region... "
    RESULT=$(aws ec2 import-key-pair \
        --region $region \
        --key-name $KEY_NAME \
        --public-key-material "$PUBLIC_KEY" \
        --output text 2>&1)
    
    if echo "$RESULT" | grep -q "key-fingerprint\|$KEY_NAME"; then
        echo "✓"
        IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
    else
        echo "❌ Failed: $RESULT"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Key pair import complete!"
echo ""
echo "Summary:"
echo "  - Imported to: $IMPORTED_COUNT regions"
echo "  - Already existed: $EXISTING_COUNT regions"
if [ $FAILED_COUNT -gt 0 ]; then
    echo "  - Failed: $FAILED_COUNT regions"
fi
echo ""
echo "You can now create instances in any region using this key pair!"
