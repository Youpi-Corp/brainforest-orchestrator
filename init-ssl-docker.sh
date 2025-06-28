#!/bin/bash

# SSL Initialization Script for Docker Environment
# This script sets up SSL certificates using Certbot in a Docker environment

set -e

# Configuration
DOMAIN="brain-forest.works"
API_DOMAIN="api.brain-forest.works"
EMAIL="your-email@example.com"  # Update this with your email
COMPOSE_FILE="docker-compose.yml"
SSL_COMPOSE_FILE="docker-compose.ssl.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create necessary directories
print_status "Creating SSL directories..."
mkdir -p ./ssl/certbot/conf
mkdir -p ./ssl/certbot/www
mkdir -p ./ssl/dhparam

# Generate DH parameters if they don't exist
if [ ! -f "./ssl/dhparam/dhparam.pem" ]; then
    print_status "Generating DH parameters (this may take a few minutes)..."
    openssl dhparam -out ./ssl/dhparam/dhparam.pem 2048
else
    print_status "DH parameters already exist"
fi

# Check if this is the first time setup
if [ ! -d "./ssl/certbot/conf/live/$DOMAIN" ]; then
    print_status "First time SSL setup detected"
    
    # Create temporary nginx config for initial certificate request
    print_status "Creating temporary nginx configuration for certificate request..."
    
    # Start services without SSL first
    print_status "Starting services for initial setup..."
    docker compose -f $COMPOSE_FILE up -d
    
    # Wait for services to be ready
    sleep 10
    
    # Request initial certificates
    print_status "Requesting initial SSL certificates..."
    docker compose -f $SSL_COMPOSE_FILE run --rm certbot \
        certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --domains $DOMAIN,$API_DOMAIN,www.$DOMAIN \
        --non-interactive
    
    if [ $? -eq 0 ]; then
        print_status "✅ Initial certificates obtained successfully"
    else
        print_error "Failed to obtain initial certificates"
        exit 1
    fi
    
    # Stop the initial setup
    docker compose -f $COMPOSE_FILE down
    
else
    print_status "Existing certificates found"
fi

# Start the full SSL-enabled stack
print_status "Starting SSL-enabled services..."
docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE up -d

# Wait for nginx to start
sleep 5

# Test nginx configuration
print_status "Testing nginx configuration..."
docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE exec nginx nginx -t

if [ $? -eq 0 ]; then
    print_status "✅ Nginx configuration is valid"
    
    # Reload nginx
    docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE exec nginx nginx -s reload
    
    print_status "✅ SSL-enabled Brain Forest is now running!"
    print_status "Your sites should be accessible at:"
    print_status "  - https://$DOMAIN"
    print_status "  - https://www.$DOMAIN" 
    print_status "  - https://$API_DOMAIN"
    
else
    print_error "Nginx configuration test failed"
    print_status "Checking nginx logs..."
    docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE logs nginx
    exit 1
fi

# Set up certificate renewal check
print_status "Setting up certificate renewal..."
print_status "Certificates will be automatically renewed by the certbot container"

# Test certificate renewal
print_status "Testing certificate renewal process..."
docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE exec certbot certbot renew --dry-run

if [ $? -eq 0 ]; then
    print_status "✅ Certificate renewal test passed"
else
    print_warning "Certificate renewal test failed - certificates may not renew automatically"
fi

print_status "🎉 SSL setup complete!"
print_warning "Remember to:"
print_warning "1. Update the email address in this script: $EMAIL"
print_warning "2. Ensure your domain DNS points to this server"
print_warning "3. Open ports 80 and 443 in your firewall"

print_status "To check certificate status:"
print_status "  docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE exec certbot certbot certificates"

print_status "To manually renew certificates:"
print_status "  docker compose -f $COMPOSE_FILE -f $SSL_COMPOSE_FILE exec certbot certbot renew"
