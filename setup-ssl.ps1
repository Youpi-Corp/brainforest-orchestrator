# Certbot SSL Certificate Setup Script for Brain Forest (PowerShell)
# This script helps set up Let's Encrypt SSL certificates using Certbot

param(
    [string]$Email = "your-email@example.com",
    [string]$Domain = "brain-forest.works",
    [string]$ApiDomain = "api.brain-forest.works"
)

# Configuration
$WebrootPath = "/var/www/certbot"

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

Write-Status "🔐 Setting up SSL certificates for Brain Forest..."

# Check if running in Docker/WSL environment
if ($IsLinux -or $env:WSL_DISTRO_NAME) {
    Write-Status "Detected Linux/WSL environment"
    
    # Check if Certbot is installed
    $certbotExists = Get-Command certbot -ErrorAction SilentlyContinue
    
    if (-not $certbotExists) {
        Write-Status "Installing Certbot..."
        
        # Install Certbot based on distribution
        if (Test-Path "/etc/debian_version") {
            sudo apt-get update
            sudo apt-get install -y certbot python3-certbot-nginx
        }
        elseif (Test-Path "/etc/redhat-release") {
            sudo yum install -y certbot python3-certbot-nginx
        }
        else {
            Write-Error "Unsupported Linux distribution. Please install Certbot manually."
            exit 1
        }
    }
    else {
        Write-Status "Certbot is already installed"
    }
    
    # Create webroot directory
    sudo mkdir -p $WebrootPath
    sudo chown -R www-data:www-data $WebrootPath 2>$null -or sudo chown -R nginx:nginx $WebrootPath 2>$null
    
    # Check if certificates exist
    if (Test-Path "/etc/letsencrypt/live/$Domain") {
        Write-Warning "Certificates for $Domain already exist"
        $renew = Read-Host "Do you want to renew them? (y/n)"
        
        if ($renew -eq "y" -or $renew -eq "Y") {
            Write-Status "Renewing certificates..."
            sudo certbot renew --nginx
        }
    }
    else {
        Write-Status "Obtaining new certificates for $Domain and $ApiDomain..."
        
        # Obtain certificates
        sudo certbot certonly `
            --webroot `
            --webroot-path="$WebrootPath" `
            --email "$Email" `
            --agree-tos `
            --no-eff-email `
            --domains "$Domain,$ApiDomain,www.$Domain" `
            --non-interactive
    }
    
    # Test nginx configuration
    Write-Status "Testing nginx configuration..."
    $nginxTest = sudo nginx -t
    
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Nginx configuration is valid"
        
        # Reload nginx
        Write-Status "Reloading nginx..."
        sudo systemctl reload nginx
        
        Write-Status "✅ SSL certificates have been successfully configured!"
        Write-Status "Your sites should now be accessible via HTTPS:"
        Write-Status "  - https://$Domain"
        Write-Status "  - https://www.$Domain"
        Write-Status "  - https://$ApiDomain"
    }
    else {
        Write-Error "Nginx configuration test failed. Please check your configuration."
        exit 1
    }
    
    # Set up automatic renewal
    Write-Status "Setting up automatic certificate renewal..."
    
    $renewalScript = @"
#!/bin/bash
# Automatic certificate renewal script

# Renew certificates
certbot renew --quiet --nginx

# Reload nginx if certificates were renewed
if [ `$? -eq 0 ]; then
    systemctl reload nginx
fi
"@
    
    $renewalScript | sudo tee /etc/cron.daily/certbot-renew > $null
    sudo chmod +x /etc/cron.daily/certbot-renew
    
    Write-Status "✅ Automatic renewal has been configured"
    
    # Test renewal
    Write-Status "Testing certificate renewal process..."
    sudo certbot renew --dry-run
    
    if ($LASTEXITCODE -eq 0) {
        Write-Status "✅ Certificate renewal test passed"
    }
    else {
        Write-Warning "Certificate renewal test failed. Please check your configuration."
    }
}
else {
    Write-Status "For Windows Docker Desktop, please ensure you're running this in a Linux container or WSL environment."
    Write-Status "Alternatively, use the bash script: setup-ssl.sh"
}

Write-Status "🎉 SSL setup process complete!"
Write-Warning "Don't forget to update the email address: $Email"

# Display manual steps for Docker setup
Write-Status "`nFor Docker environments, you may need to:"
Write-Status "1. Ensure the nginx container has access to /etc/letsencrypt"
Write-Status "2. Mount the certificates directory as a volume"
Write-Status "3. Set up a separate certbot container or run certbot on the host"
