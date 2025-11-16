#!/bin/bash
# AWS Setup Script for V2VBot
# This script sets up AWS CLI and authentication

set -e

REGION="ap-south-2"  # Hyderabad, India (or change to your preferred region)

echo "🚀 Setting up AWS for V2VBot..."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installing AWS CLI on macOS..."
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
    else
        echo "Please install AWS CLI manually: https://aws.amazon.com/cli/"
        exit 1
    fi
fi

echo "✓ AWS CLI found"

# Check if AWS is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo ""
    echo "📝 AWS CLI not configured. Running 'aws configure'..."
    echo "   You'll need:"
    echo "   - AWS Access Key ID"
    echo "   - AWS Secret Access Key"
    echo "   - Default region: $REGION (or your preferred region)"
    echo "   - Default output format: json"
    echo ""
    aws configure
else
    echo "✓ AWS CLI already configured"
fi

# Get current identity
echo ""
echo "🔐 Verifying authentication..."
CURRENT_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null || echo "")
if [ -z "$CURRENT_IDENTITY" ]; then
    echo "❌ Authentication failed. Please run 'aws configure'"
    exit 1
fi

ACCOUNT_ID=$(echo "$CURRENT_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CURRENT_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

echo "✓ Authenticated as: $USER_ARN"
echo "✓ Account ID: $ACCOUNT_ID"

# Set default region
CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "")
if [ "$CURRENT_REGION" != "$REGION" ]; then
    echo ""
    echo "📍 Setting default region to $REGION..."
    aws configure set default.region $REGION
    echo "✓ Default region set to $REGION"
else
    echo "✓ Default region: $REGION"
fi

echo ""
echo "✅ AWS setup complete!"
echo ""
echo "Next steps:"
echo "1. Run: ./aws/aws_create_instance.sh to create the EC2 instance"
echo "2. Run: ./aws/aws_start_instance.sh to start the instance when needed"
echo "3. Run: ./aws/aws_stop_instance.sh to stop the instance and save costs"
echo ""

