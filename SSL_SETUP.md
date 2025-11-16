# SSL/HTTPS Setup Guide

## Problem
Modern browsers require HTTPS (or localhost) to access `getUserMedia()` API for microphone access. Without HTTPS, you'll see errors like:
```
TypeError: Cannot read properties of undefined (reading 'getUserMedia')
```

## Solution
This project now supports HTTPS with two options:

### Option 1: Self-Signed Certificate (Quick Testing)
A self-signed certificate has already been created for immediate testing.

**To use it:**
```bash
./start.sh
```

**Access your app:**
- Use `https://your-server-ip:8000` (note the `https://`)
- Your browser will show a security warning (this is normal for self-signed certs)
- Click "Advanced" → "Proceed to site" to continue

### Option 2: Let's Encrypt (Production)
For production use with a real domain name, use Let's Encrypt:

**Prerequisites:**
- A domain name pointing to your server's IP address
- Port 80 accessible from the internet
- Email address for Let's Encrypt notifications

**Setup:**
```bash
DOMAIN=yourdomain.com EMAIL=your@email.com ./setup_ssl.sh
```

**Example:**
```bash
DOMAIN=v2vbot.example.com EMAIL=admin@example.com ./setup_ssl.sh
```

The script will:
1. Install certbot if needed
2. Obtain a certificate from Let's Encrypt
3. Copy certificates to the `ssl/` directory
4. Configure the server to use them

**Auto-renewal:**
Let's Encrypt certificates expire in 90 days. Set up auto-renewal:
```bash
sudo certbot renew --dry-run  # Test renewal
sudo systemctl enable certbot.timer  # Enable auto-renewal
```

## Configuration

### Environment Variables
You can customize SSL certificate paths:
```bash
export SSL_CERT=/path/to/cert.pem
export SSL_KEY=/path/to/key.pem
./start.sh
```

### Manual Certificate Generation
If you need to regenerate the self-signed certificate:
```bash
./setup_ssl.sh
```

## Troubleshooting

### Browser shows "Not Secure" warning
- **Self-signed certs**: This is expected. Click "Advanced" → "Proceed to site"
- **Let's Encrypt**: Check that your domain DNS points to the correct IP

### Port 443 not accessible
- Check firewall: `sudo ufw allow 443/tcp`
- Check if port is in use: `sudo lsof -i :443`

### Certificate errors
- Verify certificate exists: `ls -la ssl/`
- Check certificate validity: `openssl x509 -in ssl/cert.pem -text -noout`
- Regenerate if needed: `./setup_ssl.sh`

### getUserMedia still not working
- Make sure you're using `https://` not `http://`
- Check browser console for specific errors
- Some browsers require user interaction before allowing mic access

## Security Notes

- **Never commit SSL private keys to git** (already in `.gitignore`)
- Self-signed certificates are for testing only
- Use Let's Encrypt for production deployments
- Keep certificates updated and renew before expiration
