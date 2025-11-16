#!/usr/bin/env bash
# SSL Setup Script for V2VBot
# This script sets up HTTPS using Let's Encrypt or creates a self-signed certificate

set -euo pipefail

SSL_DIR="ssl"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"

echo "=========================================="
echo "🔒 V2VBot SSL Setup"
echo "=========================================="
echo ""

# Create SSL directory
mkdir -p "$SSL_DIR"

# Function to create self-signed certificate
create_self_signed() {
	echo "📝 Creating self-signed certificate for testing..."
	echo ""
	
	# Get hostname or IP
	HOSTNAME=$(hostname -f 2>/dev/null || hostname || echo "localhost")
	PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
	
	if [ -n "$PUBLIC_IP" ]; then
		CN="$PUBLIC_IP"
		SAN="IP:$PUBLIC_IP"
	else
		CN="$HOSTNAME"
		SAN="DNS:$HOSTNAME"
	fi
	
	# Create self-signed certificate with SAN
	openssl req -x509 -newkey rsa:4096 \
		-keyout "$SSL_DIR/key.pem" \
		-out "$SSL_DIR/cert.pem" \
		-days 365 \
		-nodes \
		-subj "/C=US/ST=State/L=City/O=V2VBot/CN=$CN" \
		-addext "subjectAltName=$SAN" \
		2>/dev/null
	
	chmod 600 "$SSL_DIR/key.pem"
	chmod 644 "$SSL_DIR/cert.pem"
	
	echo "✅ Self-signed certificate created!"
	echo "   Certificate: $SSL_DIR/cert.pem"
	echo "   Private Key: $SSL_DIR/key.pem"
	echo ""
	echo "⚠️  Note: Browsers will show a security warning for self-signed certificates."
	echo "   This is normal for testing. Click 'Advanced' → 'Proceed to site'."
	echo ""
}

# Function to setup Let's Encrypt
setup_letsencrypt() {
	local domain=$1
	local email=$2
	
	echo "📝 Setting up Let's Encrypt for domain: $domain"
	echo ""
	
	# Check if certbot is installed
	if ! command -v certbot &> /dev/null; then
		echo "📦 Installing certbot..."
		sudo apt-get update -qq
		sudo apt-get install -y certbot python3-certbot-nginx 2>/dev/null || {
			echo "❌ Failed to install certbot. Please install manually:"
			echo "   sudo apt-get install -y certbot python3-certbot-nginx"
			return 1
		}
	fi
	
	# Check if port 80 is accessible (required for Let's Encrypt)
	if ! sudo netstat -tuln | grep -q ':80 '; then
		echo "⚠️  Warning: Port 80 is not open. Let's Encrypt requires port 80 for validation."
		echo "   Make sure port 80 is accessible from the internet."
		read -p "Continue anyway? (y/n) " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			return 1
		fi
	fi
	
	# Stop any server running on port 80
	if sudo lsof -ti:80 > /dev/null 2>&1; then
		echo "⚠️  Port 80 is in use. Stopping existing service..."
		sudo systemctl stop nginx 2>/dev/null || true
		sudo pkill -f "uvicorn.*--port.*80" 2>/dev/null || true
	fi
	
	# Run certbot in standalone mode
	echo "🔐 Obtaining certificate from Let's Encrypt..."
	sudo certbot certonly --standalone \
		--non-interactive \
		--agree-tos \
		--email "$email" \
		-d "$domain" \
		--preferred-challenges http \
		|| {
		echo "❌ Failed to obtain certificate. Common issues:"
		echo "   1. Domain must point to this server's IP"
		echo "   2. Port 80 must be accessible from internet"
		echo "   3. Firewall must allow incoming connections on port 80"
		return 1
	}
	
	# Copy certificates to project directory
	CERT_PATH="/etc/letsencrypt/live/$domain"
	if [ -d "$CERT_PATH" ]; then
		sudo cp "$CERT_PATH/fullchain.pem" "$SSL_DIR/cert.pem"
		sudo cp "$CERT_PATH/privkey.pem" "$SSL_DIR/key.pem"
		sudo chown "$USER:$USER" "$SSL_DIR/cert.pem" "$SSL_DIR/key.pem"
		chmod 600 "$SSL_DIR/key.pem"
		chmod 644 "$SSL_DIR/cert.pem"
		
		echo "✅ Let's Encrypt certificate installed!"
		echo "   Certificate: $SSL_DIR/cert.pem"
		echo "   Private Key: $SSL_DIR/key.pem"
		echo ""
		echo "📅 Certificate expires in 90 days."
		echo "   To renew: sudo certbot renew"
		echo "   Or set up auto-renewal: sudo certbot renew --dry-run"
		return 0
	else
		echo "❌ Certificate files not found at $CERT_PATH"
		return 1
	fi
}

# Main setup logic
if [ -n "$DOMAIN" ]; then
	# Use Let's Encrypt if domain is provided
	if [ -z "$EMAIL" ]; then
		echo "❌ Error: EMAIL environment variable is required for Let's Encrypt"
		echo "   Usage: DOMAIN=yourdomain.com EMAIL=your@email.com ./setup_ssl.sh"
		exit 1
	fi
	
	if setup_letsencrypt "$DOMAIN" "$EMAIL"; then
		echo "✅ SSL setup complete with Let's Encrypt!"
		exit 0
	else
		echo "⚠️  Let's Encrypt setup failed. Falling back to self-signed certificate..."
		create_self_signed
	fi
else
	# Use self-signed certificate
	echo "ℹ️  No domain specified. Creating self-signed certificate for testing."
	echo "   For production with Let's Encrypt, run:"
	echo "   DOMAIN=yourdomain.com EMAIL=your@email.com ./setup_ssl.sh"
	echo ""
	create_self_signed
fi

echo ""
echo "=========================================="
echo "✅ SSL Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Restart your server: ./start.sh"
echo "2. Access your app at: https://your-server-ip:8000"
echo ""
