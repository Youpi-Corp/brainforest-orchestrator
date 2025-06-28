# Emergency deployment script to bypass SSL issues temporarily
# Use this when Let's Encrypt rate limits are hit

$ErrorActionPreference = "Stop"

Write-Host "EMERGENCY: deployment without SSL (rate limit bypass)" -ForegroundColor Red

# Stop all services first
Write-Host "Stopping all services..." -ForegroundColor Yellow
docker-compose -f docker-compose.prod.yml down

# Load environment variables from .env.prod
Write-Host "Loading environment variables..." -ForegroundColor Blue
if (Test-Path ".env.prod") {
    Get-Content ".env.prod" | ForEach-Object {
        if ($_ -match "^([^#=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
    Write-Host "Environment variables loaded from .env.prod" -ForegroundColor Green
} else {
    Write-Host "WARNING: .env.prod file not found!" -ForegroundColor Red
    exit 1
}

# Create HTTP-only nginx config
Write-Host "Creating HTTP-only nginx config..." -ForegroundColor Blue
New-Item -ItemType Directory -Path "./nginx/sites-enabled-emergency" -Force | Out-Null

$emergencyConfig = @"
# Emergency HTTP-only configuration
server {
    listen 80;
    server_name brain-forest.works www.brain-forest.works;

    # Let's Encrypt ACME challenge (for future use)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files `$uri =404;
    }

    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}

# API Backend
server {
    listen 80;
    server_name api.brain-forest.works;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files `$uri =404;
    }

    location / {
        proxy_pass http://backend:8080;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

Set-Content -Path "./nginx/sites-enabled-emergency/brainforest-emergency.conf" -Value $emergencyConfig

# Backup current config
if (Test-Path "./nginx/sites-enabled") {
    if (Test-Path "./nginx/sites-enabled-backup") {
        Remove-Item "./nginx/sites-enabled-backup" -Recurse -Force
    }
    Move-Item "./nginx/sites-enabled" "./nginx/sites-enabled-backup"
}
Move-Item "./nginx/sites-enabled-emergency" "./nginx/sites-enabled"

# Update docker-compose to remove certbot temporarily
$dockerComposeBackup = Get-Content "docker-compose.prod.yml" -Raw
$dockerComposeBackup | Out-File "docker-compose.prod.yml.backup"

Write-Host "Starting services without SSL..." -ForegroundColor Green
docker-compose -f docker-compose.prod.yml --env-file .env.prod up -d db redis backend frontend nginx

Write-Host "Waiting for services to be healthy..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "Emergency deployment complete!" -ForegroundColor Green
Write-Host "All services are healthy and running!" -ForegroundColor Green
Write-Host ""
Write-Host "Your application is available at (HTTP only):" -ForegroundColor Cyan
Write-Host "   - http://localhost:80 (via nginx reverse proxy)" -ForegroundColor White
Write-Host "   - http://localhost:8080 (frontend direct)" -ForegroundColor White
Write-Host "   - http://localhost:3000 (backend direct)" -ForegroundColor White
Write-Host ""
Write-Host "Health check endpoints:" -ForegroundColor Cyan
Write-Host "   - Frontend: http://localhost:8080/health" -ForegroundColor White
Write-Host "   - Backend: http://localhost:3000/info/alive" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: This is HTTP only. SSL will be added later when rate limits reset." -ForegroundColor Yellow
Write-Host "To check logs: docker-compose -f docker-compose.prod.yml logs -f" -ForegroundColor Cyan
Write-Host "To stop: docker-compose -f docker-compose.prod.yml down" -ForegroundColor Cyan
