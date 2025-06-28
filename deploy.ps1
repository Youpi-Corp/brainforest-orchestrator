# 🌳 Brain Forest - Simple Deployment Script
param(
    [Parameter(Position=0)]
    [ValidateSet("deploy", "status", "logs", "stop", "restart", "backup", "clean", "help")]
    [string]$Action = "deploy",
    
    [string]$Service = "",
    [switch]$Force,
    [switch]$SkipBackup
)

# Configuration  
$EnvFile = ".env.prod"
$LogFile = "./logs/deploy.log"

# Create directories
@("./logs", "./backups") | ForEach-Object { 
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null } 
}

function Write-Log($Message, $Level = "Info") {
    $emoji = switch ($Level) {
        "Error" { "❌" }; "Warning" { "⚠️" }; "Success" { "✅" }; "Deploy" { "🚀" }
        default { "ℹ️" }
    }
    $color = switch ($Level) {
        "Error" { "Red" }; "Warning" { "Yellow" }; "Success" { "Green" }; "Deploy" { "Magenta" }
        default { "Cyan" }
    }
    Write-Host "$emoji $Message" -ForegroundColor $color
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" | Out-File -FilePath $LogFile -Append
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    try {
        docker --version | Out-Null
        docker-compose --version | Out-Null
        Write-Log "Docker and Docker Compose are available" "Success"
    } catch {
        Write-Log "Docker or Docker Compose not found! Please install Docker Desktop." "Error"
        exit 1
    }
    
    if (!(Test-Path $EnvFile)) {
        Write-Log "Environment file $EnvFile not found!" "Error"
        Write-Log "Run: Copy-Item .env.prod.example .env.prod" "Info"
        Write-Log "Then edit .env.prod with your database password" "Info"
        exit 1
    }
}

function Backup-Database {
    if ($SkipBackup) {
        Write-Log "Skipping database backup" "Warning"
        return
    }
    
    Write-Log "Creating database backup..." "Deploy"
    $backupFile = "./backups/backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
    
    try {
        docker-compose --env-file $EnvFile exec -T db pg_dump -U postgres brainforest | Out-File -FilePath $backupFile -Encoding UTF8
        if ((Get-Item $backupFile).Length -gt 0) {
            Compress-Archive -Path $backupFile -DestinationPath "$backupFile.zip" -Force
            Remove-Item $backupFile
            Write-Log "Database backup created: $backupFile.zip" "Success"
        }
    } catch {
        Write-Log "Database backup failed (this is normal on first deployment)" "Warning"
    }
}

function Deploy-Application {
    Write-Host "`n🌳 DEPLOYING BRAIN FOREST APPLICATION" -ForegroundColor Magenta
    Write-Host "=" * 50 -ForegroundColor Magenta
    
    Write-Log "Pulling latest images..." "Deploy"
    docker-compose --env-file $EnvFile pull
    
    Write-Log "Building and starting services..." "Deploy"
    docker-compose --env-file $EnvFile up -d --build
    
    Write-Log "Waiting for services to be ready..." "Deploy"
    Start-Sleep 30
    
    # Test endpoints
    $endpoints = @(
        @{Name="Frontend"; Url="http://localhost:8080"},
        @{Name="Backend"; Url="http://localhost:3000/info/alive"}
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.Url -UseBasicParsing -TimeoutSec 10
            Write-Log "$($endpoint.Name): Status $($response.StatusCode)" "Success"
        } catch {
            Write-Log "$($endpoint.Name): Not responding yet (may need more time)" "Warning"
        }
    }
    
    Write-Log "🎉 Deployment completed!" "Success"
    Write-Host ""
    Write-Log "🌐 Frontend: http://localhost:8080" "Success"
    Write-Log "🔌 Backend: http://localhost:3000" "Success"
    Write-Host ""
}

function Show-Status {
    Write-Host "`n📊 APPLICATION STATUS" -ForegroundColor Cyan
    Write-Host "=" * 30 -ForegroundColor Cyan
    
    docker-compose --env-file $EnvFile ps
    
    Write-Host "`n📈 Resource Usage:" -ForegroundColor Cyan
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

function Show-Logs {
    if ($Service) {
        Write-Log "Showing logs for $Service..."
        docker-compose --env-file $EnvFile logs -f $Service
    } else {
        Write-Log "Showing logs for all services..."
        docker-compose --env-file $EnvFile logs -f
    }
}

function Stop-Services {
    Write-Log "Stopping all services..." "Warning"
    docker-compose --env-file $EnvFile down
    Write-Log "All services stopped" "Success"
}

function Restart-Services {
    Write-Log "Restarting services..." "Deploy"
    docker-compose --env-file $EnvFile restart
    Write-Log "Services restarted" "Success"
}

function Clean-Environment {
    Write-Log "Cleaning Docker environment..." "Warning"
    docker-compose --env-file $EnvFile down --remove-orphans
    docker image prune -f
    if ($Force) {
        docker volume prune -f
        Write-Log "Unused volumes removed" "Success"
    }
    Write-Log "Environment cleaned" "Success"
}

function Show-Help {
    Write-Host @"

🌳 Brain Forest Deployment Script

USAGE:
  .\deploy.ps1 [ACTION] [OPTIONS]

ACTIONS:
  deploy     Deploy the application (default)
  status     Show application status  
  logs       Show logs (-Service for specific service)
  stop       Stop all services
  restart    Restart services
  backup     Create database backup
  clean      Clean Docker resources (-Force to remove volumes)
  help       Show this help

EXAMPLES:
  .\deploy.ps1                          # Deploy application
  .\deploy.ps1 status                   # Check status
  .\deploy.ps1 logs -Service backend    # View backend logs
  .\deploy.ps1 clean -Force             # Clean everything

FIRST TIME SETUP:
  1. Copy-Item .env.prod.example .env.prod
  2. Edit .env.prod with your database password
  3. .\deploy.ps1 deploy

"@ -ForegroundColor Cyan
}

# Main execution
try {
    switch ($Action) {
        "deploy" {
            Test-Prerequisites
            Backup-Database
            Deploy-Application
        }
        "status" { 
            Test-Prerequisites
            Show-Status 
        }
        "logs" { 
            Test-Prerequisites
            Show-Logs 
        }
        "stop" { 
            Test-Prerequisites
            Stop-Services 
        }
        "restart" { 
            Test-Prerequisites
            Restart-Services 
        }
        "backup" { 
            Test-Prerequisites
            Backup-Database 
        }
        "clean" { Clean-Environment }
        "help" { Show-Help }
    }
} catch {
    Write-Log "Operation failed: $($_.Exception.Message)" "Error"
    exit 1
}

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
