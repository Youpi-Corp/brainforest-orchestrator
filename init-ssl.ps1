# SSL Certificate initialization script for Windows/PowerShell
param(
    [string]$EnvFile = ".env.prod",
    [string]$ComposeFile = "docker-compose.prod.yml"
)

# Logging functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] ${Level}: $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
}

# Check if environment file exists
if (!(Test-Path $EnvFile)) {
    Write-Log "Environment file $EnvFile not found!" "ERROR"
    Write-Log "Copy .env.prod.example to .env.prod and configure it" "INFO"
    exit 1
}

# Load environment variables
$envVars = @{}
Get-Content $EnvFile | Where-Object { $_ -match "^[^#].*=" } | ForEach-Object {
    $key, $value = $_ -split '=', 2
    if ($key -and $value) {
        $envVars[$key.Trim()] = $value.Trim()
    }
}

$sslEmail = $envVars["SSL_EMAIL"]
$domainName = $envVars["DOMAIN_NAME"]
$apiDomain = $envVars["API_DOMAIN"]

# Validate required variables
if (-not $sslEmail -or -not $domainName -or -not $apiDomain) {
    Write-Log "SSL configuration incomplete!" "ERROR"
    Write-Log "Please set SSL_EMAIL, DOMAIN_NAME, and API_DOMAIN in $EnvFile" "ERROR"
    exit 1
}

Write-Log "🔐 Initializing SSL certificates with Let's Encrypt" "SUCCESS"
Write-Log "Domain: $domainName" "INFO"
Write-Log "API Domain: $apiDomain" "INFO"
Write-Log "Email: $sslEmail" "INFO"

try {
    # Create necessary directories
    if (!(Test-Path "./logs/certbot")) { New-Item -ItemType Directory -Path "./logs/certbot" -Force }

    # Check if certificates already exist
    $volumeExists = docker volume ls --format "{{.Name}}" | Where-Object { $_ -match "letsencrypt_certs" }
    
    if ($volumeExists) {
        Write-Log "SSL certificates volume already exists" "WARNING"
        Write-Log "Checking certificate status..." "INFO"
        
        # Start nginx temporarily
        docker-compose -f $ComposeFile --env-file $EnvFile up -d nginx
        Start-Sleep 5
        
        # Check if certificates exist
        $certExists = docker-compose -f $ComposeFile --env-file $EnvFile exec nginx ls /etc/letsencrypt/live/$domainName/fullchain.pem 2>$null
        
        if ($certExists) {
            Write-Log "✅ SSL certificates already exist and are mounted" "SUCCESS"
            
            # Get certificate expiry
            $certInfo = docker-compose -f $ComposeFile --env-file $EnvFile exec nginx openssl x509 -in /etc/letsencrypt/live/$domainName/fullchain.pem -noout -enddate
            Write-Log "Certificate info: $certInfo" "INFO"
            
            return
        }
    }

    Write-Log "🚀 Starting initial SSL certificate setup..." "SUCCESS"

    # Start nginx for ACME challenges
    Write-Log "Starting Nginx for ACME challenge..." "INFO"
    docker-compose -f $ComposeFile --env-file $EnvFile up -d nginx
    Start-Sleep 10

    # Obtain certificates using Certbot
    Write-Log "🔒 Obtaining SSL certificates from Let's Encrypt..." "SUCCESS"
    
    $certbotCmd = "certbot certonly --webroot --webroot-path=/var/www/certbot --email $sslEmail --agree-tos --no-eff-email --non-interactive -d $domainName -d www.$domainName -d $apiDomain"
    
    $result = docker-compose -f $ComposeFile --env-file $EnvFile run --rm certbot $certbotCmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✅ SSL certificates obtained successfully!" "SUCCESS"
        
        # Reload nginx
        Write-Log "Reloading Nginx with new certificates..." "INFO"
        docker-compose -f $ComposeFile --env-file $EnvFile exec nginx nginx -s reload
        
        # Start certbot renewal service
        Write-Log "🔄 Starting automatic certificate renewal service..." "SUCCESS"
        docker-compose -f $ComposeFile --env-file $EnvFile up -d certbot
        
        Write-Log "🎉 SSL setup completed successfully!" "SUCCESS"
        Write-Log "Your certificates will be automatically renewed every 12 hours" "INFO"
        
        # Test HTTPS endpoints
        Write-Log "Testing HTTPS endpoints..." "INFO"
        Start-Sleep 5
        
        try {
            $frontendTest = Invoke-WebRequest -Uri "https://$domainName/health" -UseBasicParsing -TimeoutSec 10
            Write-Log "✅ Frontend HTTPS is working" "SUCCESS"
        } catch {
            Write-Log "⚠️ Frontend HTTPS test failed - this might be normal if frontend isn`'t ready yet" "WARNING"
        }
        
        try {
            $apiTest = Invoke-WebRequest -Uri "https://$apiDomain/info/alive" -UseBasicParsing -TimeoutSec 10
            Write-Log "✅ API HTTPS is working" "SUCCESS"
        } catch {
            Write-Log "⚠️ API HTTPS test failed - this might be normal if backend isn`'t ready yet" "WARNING"
        }
        
    } else {
        Write-Log "❌ Failed to obtain SSL certificates" "ERROR"
        Write-Log "Please check:" "ERROR"
        Write-Log "1. DNS records point to this server" "ERROR"
        Write-Log "2. Ports 80 and 443 are open" "ERROR"
        Write-Log "3. Domain is accessible from the internet" "ERROR"
        Write-Log "4. Email address is valid" "ERROR"
        
        # Show certbot logs
        Write-Log "Certbot logs:" "INFO"
        docker-compose -f $ComposeFile --env-file $EnvFile logs certbot
        
        exit 1
    }

} catch {
    Write-Log "SSL setup failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

Write-Log "🔐 SSL Certificate setup completed!" "SUCCESS"
Write-Log "Certificates are stored in Docker volume and will be automatically renewed" "INFO"
