#!/bin/bash

# SSL Certificate initialization script for production deployment
set -e

# Configuration
ENV_FILE=".env.prod"
COMPOSE_FILE="docker-compose.prod.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    error "Environment file $ENV_FILE not found!"
    info "Copy .env.prod.example to .env.prod and configure it"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

# Validate required variables
if [ -z "$SSL_EMAIL" ] || [ -z "$DOMAIN_NAME" ] || [ -z "$API_DOMAIN" ]; then
    error "SSL configuration incomplete!"
    error "Please set SSL_EMAIL, DOMAIN_NAME, and API_DOMAIN in $ENV_FILE"
    exit 1
fi

log "🔐 Initializing SSL certificates with Let's Encrypt"
info "Domain: $DOMAIN_NAME"
info "API Domain: $API_DOMAIN"
info "Email: $SSL_EMAIL"

# Create necessary directories
mkdir -p ./logs/certbot

# Check if certificates already exist
if docker volume ls | grep -q "letsencrypt_certs"; then
    warning "SSL certificates volume already exists"
    info "Checking certificate status..."
    
    # Start nginx temporarily for certificate validation
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d nginx
    sleep 5
    
    # Check if certificates exist and are valid
    if docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec nginx ls -la /etc/letsencrypt/live/"$DOMAIN_NAME"/fullchain.pem 2>/dev/null; then
        log "✅ SSL certificates already exist and are mounted"
        
        # Test certificate validity
        CERT_EXPIRY=$(docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec nginx openssl x509 -in /etc/letsencrypt/live/"$DOMAIN_NAME"/fullchain.pem -noout -enddate | cut -d= -f2)
        info "Certificate expires: $CERT_EXPIRY"
        
        # Check if certificate expires in less than 30 days
        EXPIRY_TIMESTAMP=$(date -d "$CERT_EXPIRY" +%s)
        CURRENT_TIMESTAMP=$(date +%s)
        DAYS_UNTIL_EXPIRY=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / 86400 ))
        
        if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
            warning "Certificate expires in $DAYS_UNTIL_EXPIRY days. Consider renewal."
        else
            log "Certificate is valid for $DAYS_UNTIL_EXPIRY more days"
        fi
        
        exit 0
    fi
fi

log "🚀 Starting initial SSL certificate setup..."

# Start nginx first to handle ACME challenges
info "Starting Nginx for ACME challenge..."
docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d nginx

# Wait for nginx to be ready
sleep 10

# Test if nginx is responding
if ! curl -f http://localhost/.well-known/acme-challenge/test 2>/dev/null; then
    info "Nginx is ready for ACME challenges"
fi

# Generate initial certificates using Certbot
log "🔒 Obtaining SSL certificates from Let's Encrypt..."

# Run certbot to obtain certificates
if docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" run --rm certbot \
    certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$SSL_EMAIL" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    -d "$DOMAIN_NAME" \
    -d "www.$DOMAIN_NAME" \
    -d "$API_DOMAIN"; then
    
    log "✅ SSL certificates obtained successfully!"
    
    # Reload nginx to use the new certificates
    info "Reloading Nginx with new certificates..."
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec nginx nginx -s reload
    
    # Start certbot service for automatic renewal
    log "🔄 Starting automatic certificate renewal service..."
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d certbot
    
    log "🎉 SSL setup completed successfully!"
    log "Your certificates will be automatically renewed every 12 hours"
    
    # Test HTTPS endpoints
    info "Testing HTTPS endpoints..."
    sleep 5
    
    if curl -f -s https://"$DOMAIN_NAME"/health >/dev/null 2>&1; then
        log "✅ Frontend HTTPS is working"
    else
        warning "⚠️ Frontend HTTPS test failed - this might be normal if frontend isn't ready yet"
    fi
    
    if curl -f -s https://"$API_DOMAIN"/info/alive >/dev/null 2>&1; then
        log "✅ API HTTPS is working"
    else
        warning "⚠️ API HTTPS test failed - this might be normal if backend isn't ready yet"
    fi
    
else
    error "❌ Failed to obtain SSL certificates"
    error "Please check:"
    error "1. DNS records point to this server"
    error "2. Ports 80 and 443 are open"
    error "3. Domain is accessible from the internet"
    error "4. Email address is valid"
    
    # Show certbot logs for debugging
    info "Certbot logs:"
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs certbot
    
    exit 1
fi

log "🔐 SSL Certificate setup completed!"
log "Certificates location: /var/lib/docker/volumes/$(basename $(pwd))_letsencrypt_certs/_data"
log "Renewal service is running automatically"
