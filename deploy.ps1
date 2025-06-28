# Production deployment script for Windows/PowerShell
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("deploy", "rollback", "backup", "logs", "status", "stop", "restart", "ssl")]
    [string]$Action,
    
    [string]$Service = "",
    
    [string]$EnvFile = ".env.prod",
    
    [string]$ComposeFile = "docker-compose.prod.yml"
)

# Configuration
$BackupDir = "./backups"
$LogFile = "./logs/deploy.log"

# Ensure directories exist
if (!(Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force }
if (!(Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" -Force }

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
    
    $logMessage | Out-File -FilePath $script:LogFile -Append
}

function Test-EnvFile {
    if (!(Test-Path $EnvFile)) {
        Write-Log "Environment file $EnvFile not found!" "ERROR"
        Write-Log "Copy .env.prod.example to .env.prod and configure it" "INFO"
        exit 1
    }
}

function Backup-Database {
    Write-Log "Creating database backup..."
    
    $backupFile = "$BackupDir/backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
    
    try {
        # Get database credentials from env file
        $envVars = @{}
        Get-Content $EnvFile | Where-Object { $_ -match "^[^#].*=" } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            if ($key -and $value) {
                $envVars[$key.Trim()] = $value.Trim()
            }
        }
        
        $dbUser = $envVars["POSTGRES_USER"]
        $dbName = $envVars["POSTGRES_DB"]
        
        # Create backup
        docker-compose -f $ComposeFile --env-file $EnvFile exec -T db pg_dump -U $dbUser $dbName | Out-File -FilePath $backupFile -Encoding UTF8
        
        Write-Log "Database backup created: $backupFile" "SUCCESS"
        
        # Compress backup
        Compress-Archive -Path $backupFile -DestinationPath "$backupFile.zip"
        Remove-Item $backupFile
        Write-Log "Backup compressed: $backupFile.zip" "SUCCESS"
        
        # Clean old backups (keep last 30 days)
        Get-ChildItem $BackupDir -Filter "backup_*.zip" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
        Write-Log "Old backups cleaned" "INFO"
        
    } catch {
        Write-Log "Database backup failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Deploy-Application {
    Write-Log "Starting production deployment..."
    
    try {
        # Initialize SSL certificates if needed
        Write-Log "Checking SSL certificate setup..." "INFO"
        & "./init-ssl.ps1" -EnvFile $EnvFile -ComposeFile $ComposeFile
        
        # Pull latest images
        Write-Log "Pulling latest images..." "INFO"
        docker-compose -f $ComposeFile --env-file $EnvFile pull
        
        # Build and start services
        Write-Log "Building and starting services..." "INFO"
        docker-compose -f $ComposeFile --env-file $EnvFile up -d --build
        
        # Wait for services to be healthy
        Write-Log "Waiting for services to be healthy..." "INFO"
        Start-Sleep 30
        
        # Check service health
        $unhealthyServices = docker-compose -f $ComposeFile --env-file $EnvFile ps --filter "health=unhealthy" -q
        if ($unhealthyServices) {
            Write-Log "Some services are unhealthy!" "ERROR"
            docker-compose -f $ComposeFile --env-file $EnvFile ps
            throw "Unhealthy services detected"
        }
        
        Write-Log "Deployment completed successfully!" "SUCCESS"
        
        # Test SSL endpoints
        Write-Log "Testing SSL endpoints..." "INFO"
        $envVars = @{}
        Get-Content $EnvFile | Where-Object { $_ -match "^[^#].*=" } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            if ($key -and $value) {
                $envVars[$key.Trim()] = $value.Trim()
            }
        }
        $domainName = $envVars["DOMAIN_NAME"]
        $apiDomain = $envVars["API_DOMAIN"]
        
        if ($domainName) {
            try {
                $response = Invoke-WebRequest -Uri "https://$domainName" -UseBasicParsing -TimeoutSec 10
                Write-Log "✅ Frontend HTTPS working (Status: $($response.StatusCode))" "SUCCESS"
            } catch {
                Write-Log "⚠️ Frontend HTTPS test failed: $($_.Exception.Message)" "WARNING"
            }
        }
        
        if ($apiDomain) {
            try {
                $response = Invoke-WebRequest -Uri "https://$apiDomain/info/alive" -UseBasicParsing -TimeoutSec 10
                Write-Log "✅ API HTTPS working (Status: $($response.StatusCode))" "SUCCESS"
            } catch {
                Write-Log "⚠️ API HTTPS test failed: $($_.Exception.Message)" "WARNING"
            }
        }
        
    } catch {
        Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Rollback-Application {
    Write-Log "Rolling back to previous version..." "WARNING"
    
    try {
        # Stop current services
        docker-compose -f $ComposeFile --env-file $EnvFile down
        
        # Find latest backup
        $latestBackup = Get-ChildItem $BackupDir -Filter "backup_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        
        if ($latestBackup) {
            Write-Log "Restoring database from: $($latestBackup.FullName)" "INFO"
            
            # Extract and restore backup
            $tempSql = "$BackupDir/temp_restore.sql"
            Expand-Archive -Path $latestBackup.FullName -DestinationPath $BackupDir -Force
            $extractedSql = Get-ChildItem $BackupDir -Filter "backup_*.sql" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            if ($extractedSql) {
                Get-Content $extractedSql.FullName | docker-compose -f $ComposeFile --env-file $EnvFile exec -T db psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB
                Remove-Item $extractedSql.FullName
            }
        }
        
        # Start services
        docker-compose -f $ComposeFile --env-file $EnvFile up -d
        
        Write-Log "Rollback completed" "SUCCESS"
        
    } catch {
        Write-Log "Rollback failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Show-Logs {
    if ($Service) {
        docker-compose -f $ComposeFile --env-file $EnvFile logs -f $Service
    } else {
        docker-compose -f $ComposeFile --env-file $EnvFile logs -f
    }
}

function Show-Status {
    Write-Host "`n=== Service Status ===" -ForegroundColor Cyan
    docker-compose -f $ComposeFile --env-file $EnvFile ps
    
    Write-Host "`n=== Resource Usage ===" -ForegroundColor Cyan
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

# Main execution
try {
    Test-EnvFile
    
    switch ($Action) {
        "deploy" {
            Backup-Database
            Deploy-Application
        }
        "rollback" {
            Rollback-Application
        }
        "backup" {
            Backup-Database
        }
        "logs" {
            Show-Logs
        }
        "status" {
            Show-Status
        }
        "stop" {
            Write-Log "Stopping services..." "INFO"
            docker-compose -f $ComposeFile --env-file $EnvFile down
        }
        "restart" {
            Write-Log "Restarting services..." "INFO"
            docker-compose -f $ComposeFile --env-file $EnvFile restart
        }
        "ssl" {
            Write-Log "Initializing SSL certificates..." "INFO"
            & "./init-ssl.ps1" -EnvFile $EnvFile -ComposeFile $ComposeFile
        }
    }
} catch {
    Write-Log "Operation failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
