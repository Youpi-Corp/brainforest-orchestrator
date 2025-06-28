#!/bin/bash

# Production deployment startup script
# This script handles the SSL certificate chicken-and-egg problem

set -e

echo "🚀 Starting Brainforest production deployment..."

# Load environment variables
if [ -f .env.prod ]; then
    export $(grep -v '^#' .env.prod | xargs)
fi

# Check if certificates exist
if [ ! -f "./ssl/fullchain.pem" ] && [ ! -f "/etc/letsencrypt/live/${DOMAIN_NAME:-brain-forest.works}/fullchain.pem" ]; then
    echo "⚠️  SSL certificates not found. Starting without SSL first..."
    
    # Create temporary nginx config without SSL
    echo "🔧 Creating temporary nginx config..."
    mkdir -p ./nginx/sites-enabled-temp
    
    cat > ./nginx/sites-enabled-temp/brainforest-temp.conf << 'EOF'
# Temporary configuration for initial certificate generation
server {
    listen 80;
    server_name brain-forest.works www.brain-forest.works api.brain-forest.works;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    # Temporary frontend serving
    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Temporary API serving
    location /api/ {
        proxy_pass http://backend:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

    # Backup original config and use temporary
    mv ./nginx/sites-enabled ./nginx/sites-enabled-backup 2>/dev/null || true
    mv ./nginx/sites-enabled-temp ./nginx/sites-enabled
    
    echo "📦 Starting services for certificate generation..."
    docker-compose -f docker-compose.prod.yml up -d db redis backend frontend nginx
    
    # Wait for services to be ready
    echo "⏳ Waiting for services to be ready..."
    sleep 60
    
    # Get certificates
    echo "🔐 Obtaining SSL certificates..."
    docker-compose -f docker-compose.prod.yml run --rm certbot certbot certonly \
        --webroot -w /var/www/certbot \
        --email ${SSL_EMAIL} \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d ${DOMAIN_NAME:-brain-forest.works} \
        -d www.${DOMAIN_NAME:-brain-forest.works} \
        -d ${API_DOMAIN:-api.brain-forest.works} \
        --verbose
    
    # Restore original nginx config
    echo "🔧 Restoring SSL nginx configuration..."
    rm -rf ./nginx/sites-enabled
    mv ./nginx/sites-enabled-backup ./nginx/sites-enabled 2>/dev/null || true
    
    # Restart nginx with SSL config
    echo "🔄 Restarting nginx with SSL configuration..."
    docker-compose -f docker-compose.prod.yml restart nginx
fi

echo "🚀 Starting all services..."
docker-compose -f docker-compose.prod.yml up -d

echo "✅ Deployment complete!"
echo "🌐 Your application should be available at:"
echo "   - https://${DOMAIN_NAME:-brain-forest.works}"
echo "   - https://www.${DOMAIN_NAME:-brain-forest.works}" 
echo "   - https://${API_DOMAIN:-api.brain-forest.works}"

echo "📊 To check logs, run:"
echo "   docker-compose -f docker-compose.prod.yml logs -f"
