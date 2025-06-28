#!/bin/bash

# Certbot SSL Certificate Setup Script for Brain Forest
# This script sets up Let's Encrypt SSL certificates using Certbot

set -e

echo "🔐 Setting up SSL certificates for Brain Forest..."

# Configuration
DOMAIN="brain-forest.works"
API_DOMAIN="api.brain-forest.works"
EMAIL="your-email@example.com"  # Change this to your email
WEBROOT_PATH="/var/www/certbot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script as root or with sudo"
    exit 1
fi

# Install Certbot if not already installed
if ! command -v certbot &> /dev/null; then
    print_status "Installing Certbot..."
    
    # Detect OS and install accordingly
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    elif [ -f /etc/redhat-release ]; then
        yum install -y certbot python3-certbot-nginx
    else
        print_error "Unsupported OS. Please install Certbot manually."
        exit 1
    fi
else
    print_status "Certbot is already installed"
fi

# Create webroot directory if it doesn't exist
mkdir -p "$WEBROOT_PATH"
chown -R www-data:www-data "$WEBROOT_PATH" 2>/dev/null || chown -R nginx:nginx "$WEBROOT_PATH" 2>/dev/null || true

# Check if certificates already exist
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_warning "Certificates for $DOMAIN already exist"
    read -p "Do you want to renew them? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Renewing certificates..."
        certbot renew --nginx
    fi
else
    print_status "Obtaining new certificates for $DOMAIN and $API_DOMAIN..."
    
    # Obtain certificates using webroot method
    certbot certonly \
        --webroot \
        --webroot-path="$WEBROOT_PATH" \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN,$API_DOMAIN,www.$DOMAIN" \
        --non-interactive
fi

# Test nginx configuration
print_status "Testing nginx configuration..."
if nginx -t; then
    print_status "Nginx configuration is valid"
    
    # Reload nginx
    print_status "Reloading nginx..."
    systemctl reload nginx
    
    print_status "✅ SSL certificates have been successfully configured!"
    print_status "Your sites should now be accessible via HTTPS:"
    print_status "  - https://$DOMAIN"
    print_status "  - https://www.$DOMAIN"
    print_status "  - https://$API_DOMAIN"
else
    print_error "Nginx configuration test failed. Please check your configuration."
    exit 1
fi

# Set up automatic renewal
print_status "Setting up automatic certificate renewal..."

# Create renewal script
cat > /etc/cron.daily/certbot-renew << 'EOF'
#!/bin/bash
# Automatic certificate renewal script

# Renew certificates
certbot renew --quiet --nginx

# Reload nginx if certificates were renewed
if [ $? -eq 0 ]; then
    systemctl reload nginx
fi
EOF

chmod +x /etc/cron.daily/certbot-renew

print_status "✅ Automatic renewal has been configured"
print_status "Certificates will be automatically renewed via daily cron job"

# Test the renewal process
print_status "Testing certificate renewal process..."
certbot renew --dry-run

if [ $? -eq 0 ]; then
    print_status "✅ Certificate renewal test passed"
else
    print_warning "Certificate renewal test failed. Please check your configuration."
fi

print_status "🎉 SSL setup complete!"
print_warning "Don't forget to update the email address in this script: $EMAIL"
