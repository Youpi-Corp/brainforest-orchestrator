# Production deployment startup script for Windows/PowerShell
# This script handles the SSL certificate chicken-and-egg problem

$ErrorActionPreference = "Stop"

Write-Host "Starting Brainforest production deployment..." -ForegroundColor Green

# Load environment variables from .env.prod
if (Test-Path ".env.prod") {
    Get-Content ".env.prod" | ForEach-Object {
        if ($_ -match "^([^#=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
}

$domainName = $env:DOMAIN_NAME
if (!$domainName) { $domainName = "brain-forest.works" }

$apiDomain = $env:API_DOMAIN  
if (!$apiDomain) { $apiDomain = "api.brain-forest.works" }

# Check if certificates exist
$certExists = (Test-Path "./ssl/fullchain.pem") -or (Test-Path "/etc/letsencrypt/live/$domainName/fullchain.pem")

if (!$certExists) {
    Write-Host "SSL certificates not found. Starting without SSL first..." -ForegroundColor Yellow
    
    # Create temporary nginx config without SSL
    Write-Host "Creating temporary nginx config..." -ForegroundColor Blue
    New-Item -ItemType Directory -Path "./nginx/sites-enabled-temp" -Force | Out-Null
    
    $tempConfig = @"
# Temporary configuration for initial certificate generation
server {
    listen 80;
    server_name brain-forest.works www.brain-forest.works api.brain-forest.works;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files `$uri =404;
    }

    # Temporary frontend serving
    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }

    # Temporary API serving
    location /api/ {
        proxy_pass http://backend:8080/;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@
    
    Set-Content -Path "./nginx/sites-enabled-temp/brainforest-temp.conf" -Value $tempConfig
    
    # Backup original config and use temporary
    if (Test-Path "./nginx/sites-enabled") {
        if (Test-Path "./nginx/sites-enabled-backup") {
            Remove-Item "./nginx/sites-enabled-backup" -Recurse -Force
        }
        Move-Item "./nginx/sites-enabled" "./nginx/sites-enabled-backup"
    }
    Move-Item "./nginx/sites-enabled-temp" "./nginx/sites-enabled"
    
    Write-Host "Starting services for certificate generation..." -ForegroundColor Blue
    docker-compose -f docker-compose.prod.yml up -d db redis backend frontend nginx
    
    # Wait for services to be ready
    Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    
    # Get certificates
    Write-Host "Obtaining SSL certificates..." -ForegroundColor Blue
    docker-compose -f docker-compose.prod.yml run --rm certbot certbot certonly `
        --webroot -w /var/www/certbot `
        --email $env:SSL_EMAIL `
        --agree-tos `
        --no-eff-email `
        --force-renewal `
        -d $domainName `
        -d "www.$domainName" `
        -d $apiDomain `
        --verbose
    
    # Restore original nginx config
    Write-Host "Restoring SSL nginx configuration..." -ForegroundColor Blue
    Remove-Item "./nginx/sites-enabled" -Recurse -Force
    if (Test-Path "./nginx/sites-enabled-backup") {
        Move-Item "./nginx/sites-enabled-backup" "./nginx/sites-enabled"
    }
    
    # Restart nginx with SSL config
    Write-Host "Restarting nginx with SSL configuration..." -ForegroundColor Blue
    docker-compose -f docker-compose.prod.yml restart nginx
}

Write-Host "Starting all services..." -ForegroundColor Green
docker-compose -f docker-compose.prod.yml up -d

Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "Your application should be available at:" -ForegroundColor Cyan
Write-Host "   - https://$domainName" -ForegroundColor White
Write-Host "   - https://www.$domainName" -ForegroundColor White
Write-Host "   - https://$apiDomain" -ForegroundColor White

Write-Host "To check logs, run:" -ForegroundColor Cyan
Write-Host "   docker-compose -f docker-compose.prod.yml logs -f" -ForegroundColor White
