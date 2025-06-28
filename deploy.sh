#!/bin/bash

# 🌳 Brain Forest - Simple Deployment Script (Linux/macOS)
set -e

# Configuration
ENV_FILE=".env.prod"
LOG_FILE="./logs/deploy.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Create directories
mkdir -p ./logs ./backups

# Logging function
log_message() {
    local message="$1"
    local level="${2:-Info}"
    
    local emoji color
    case "$level" in
        "Error")   emoji="❌"; color="$RED" ;;
        "Warning") emoji="⚠️"; color="$YELLOW" ;;
        "Success") emoji="✅"; color="$GREEN" ;;
        "Deploy")  emoji="🚀"; color="$MAGENTA" ;;
        *)         emoji="ℹ️"; color="$CYAN" ;;
    esac
    
    echo -e "${color}${emoji} ${message}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}

check_prerequisites() {
    log_message "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_message "Docker not found! Please install Docker." "Error"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_message "Docker Compose not found! Please install Docker Compose." "Error"
        exit 1
    fi
    
    if [ ! -f "$ENV_FILE" ]; then
        log_message "Environment file $ENV_FILE not found!" "Error"
        log_message "Run: cp .env.prod.example .env.prod"
        log_message "Then edit .env.prod with your database password, domain, and email"
        exit 1
    fi
    
    # Check for required SSL environment variables
    if grep -q "DOMAIN_NAME=your-domain.com" "$ENV_FILE" 2>/dev/null; then
        log_message "Please update DOMAIN_NAME in $ENV_FILE with your actual domain!" "Error"
        exit 1
    fi
    
    if grep -q "SSL_EMAIL=your-email@example.com" "$ENV_FILE" 2>/dev/null; then
        log_message "Please update SSL_EMAIL in $ENV_FILE with your actual email!" "Error"
        exit 1
    fi
    
    log_message "Docker and Docker Compose are available" "Success"
}

backup_database() {
    if [ "$SKIP_BACKUP" = "true" ]; then
        log_message "Skipping database backup" "Warning"
        return
    fi
    
    log_message "Creating database backup..." "Deploy"
    local backup_file="./backups/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    if docker-compose --env-file "$ENV_FILE" exec -T db pg_dump -U postgres brainforest > "$backup_file" 2>/dev/null; then
        if [ -s "$backup_file" ]; then
            gzip "$backup_file"
            log_message "Database backup created: ${backup_file}.gz" "Success"
        else
            rm -f "$backup_file"
            log_message "Database backup failed (this is normal on first deployment)" "Warning"
        fi
    else
        log_message "Database backup failed (this is normal on first deployment)" "Warning"
    fi
}

deploy_application() {
    echo ""
    echo -e "${MAGENTA}🌳 DEPLOYING BRAIN FOREST APPLICATION${NC}"
    echo -e "${MAGENTA}$(printf '=%.0s' {1..50})${NC}"
    
    # Create SSL directories
    log_message "Setting up SSL directories..." "Deploy"
    mkdir -p ./ssl/certbot/conf ./ssl/certbot/www
    
    log_message "Pulling latest images..." "Deploy"
    docker-compose --env-file "$ENV_FILE" pull
    
    log_message "Building and starting services..." "Deploy"
    docker-compose --env-file "$ENV_FILE" up -d --build
    
    log_message "Waiting for services to be ready..." "Deploy"
    sleep 60  # Give more time for SSL setup
    
    # Get domain from env file
    local domain=$(grep "DOMAIN_NAME=" "$ENV_FILE" | cut -d'=' -f2)
    
    # Test endpoints
    local endpoints=("Frontend HTTP|http://localhost" "Backend API|http://localhost/api/info/alive")
    
    for endpoint in "${endpoints[@]}"; do
        IFS='|' read -r name url <<< "$endpoint"
        if curl -s -f "$url" > /dev/null 2>&1; then
            log_message "$name: Available" "Success"
        else
            log_message "$name: Not responding yet (may need more time)" "Warning"
        fi
    done
    
    # Test HTTPS if domain is configured
    if [ -n "$domain" ] && [ "$domain" != "your-domain.com" ]; then
        log_message "Testing HTTPS endpoints..." "Deploy"
        sleep 30  # Give certbot more time
        
        if curl -s -f -k "https://$domain" > /dev/null 2>&1; then
            log_message "HTTPS: Available at https://$domain" "Success"
        else
            log_message "HTTPS: Not ready yet (certificates may still be generating)" "Warning"
            log_message "Check certbot logs: docker-compose logs certbot" "Info"
        fi
    fi
    
    log_message "🎉 Deployment completed!" "Success"
    echo ""
    log_message "🌐 HTTP: http://localhost" "Success"
    if [ -n "$domain" ] && [ "$domain" != "your-domain.com" ]; then
        log_message "� HTTPS: https://$domain" "Success"
    fi
    echo ""
}

show_status() {
    echo ""
    echo -e "${CYAN}📊 APPLICATION STATUS${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..30})${NC}"
    
    docker-compose --env-file "$ENV_FILE" ps
    
    echo ""
    echo -e "${CYAN}📈 Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

show_logs() {
    if [ -n "$SERVICE" ]; then
        log_message "Showing logs for $SERVICE..."
        docker-compose --env-file "$ENV_FILE" logs -f "$SERVICE"
    else
        log_message "Showing logs for all services..."
        docker-compose --env-file "$ENV_FILE" logs -f
    fi
}

stop_services() {
    log_message "Stopping all services..." "Warning"
    docker-compose --env-file "$ENV_FILE" down
    log_message "All services stopped" "Success"
}

restart_services() {
    log_message "Restarting services..." "Deploy"
    docker-compose --env-file "$ENV_FILE" restart
    log_message "Services restarted" "Success"
}

clean_environment() {
    log_message "Cleaning Docker environment..." "Warning"
    docker-compose --env-file "$ENV_FILE" down --remove-orphans
    docker image prune -f
    if [ "$FORCE" = "true" ]; then
        docker volume prune -f
        log_message "Unused volumes removed" "Success"
    fi
    log_message "Environment cleaned" "Success"
}

check_ssl_status() {
    log_message "Checking SSL certificate status..."
    
    # Get domain from env file
    local domain=$(grep "DOMAIN_NAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    
    if [ -z "$domain" ] || [ "$domain" = "your-domain.com" ]; then
        log_message "Domain not configured in $ENV_FILE" "Warning"
        return
    fi
    
    echo ""
    echo -e "${CYAN}🔐 SSL Certificate Status${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..30})${NC}"
    
    # Check if certificates exist
    if docker-compose --env-file "$ENV_FILE" exec certbot ls /etc/letsencrypt/live/ 2>/dev/null | grep -q "$domain"; then
        log_message "SSL certificates found for $domain" "Success"
        
        # Check certificate expiry
        docker-compose --env-file "$ENV_FILE" exec certbot certbot certificates 2>/dev/null || log_message "Could not check certificate details" "Warning"
        
        # Test HTTPS connectivity
        if curl -s -f -k "https://$domain" > /dev/null 2>&1; then
            log_message "HTTPS is working: https://$domain" "Success"
        else
            log_message "HTTPS not responding at https://$domain" "Warning"
        fi
    else
        log_message "No SSL certificates found for $domain" "Warning"
        log_message "Check certbot logs: docker-compose logs certbot" "Info"
    fi
}

show_help() {
    cat << 'EOF'

🌳 Brain Forest Deployment Script

USAGE:
  ./deploy.sh [ACTION] [OPTIONS]

ACTIONS:
  deploy     Deploy the application with HTTPS (default)
  status     Show application status
  logs       Show logs (--service for specific service)
  ssl        Check SSL certificate status
  stop       Stop all services
  restart    Restart services
  backup     Create database backup
  clean      Clean Docker resources (--force to remove volumes)
  help       Show this help

OPTIONS:
  --service <name>    Specific service for logs (nginx, frontend, backend, db, certbot)
  --force             Force operations (for clean command)
  --skip-backup       Skip database backup during deployment

EXAMPLES:
  ./deploy.sh                           # Deploy with HTTPS
  ./deploy.sh status                    # Check status
  ./deploy.sh logs --service certbot    # View SSL certificate logs
  ./deploy.sh ssl                       # Check SSL status
  ./deploy.sh clean --force             # Clean everything

FIRST TIME SETUP:
  1. cp .env.prod.example .env.prod
  2. Edit .env.prod with:
     - Your database password
     - Your domain name (DOMAIN_NAME)
     - Your email for SSL certificates (SSL_EMAIL)
  3. Point your domain's DNS to this server's IP
  4. ./deploy.sh deploy

ACCESSING YOUR SITE:
  - HTTP: http://your-domain.com (redirects to HTTPS)
  - HTTPS: https://your-domain.com

EOF
}

# Parse arguments
ACTION="deploy"
SERVICE=""
FORCE="false"
SKIP_BACKUP="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        deploy|status|logs|ssl|stop|restart|backup|clean|help)
            ACTION="$1"
            shift
            ;;
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP="true"
            shift
            ;;
        *)
            log_message "Unknown option: $1" "Error"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
case "$ACTION" in
    "deploy")
        check_prerequisites
        backup_database
        deploy_application
        ;;
    "status")
        check_prerequisites
        show_status
        ;;
    "logs")
        check_prerequisites
        show_logs
        ;;
    "ssl")
        check_prerequisites
        check_ssl_status
        ;;
    "stop")
        check_prerequisites
        stop_services
        ;;
    "restart")
        check_prerequisites
        restart_services
        ;;
    "backup")
        check_prerequisites
        backup_database
        ;;
    "clean")
        clean_environment
        ;;
    "help")
        show_help
        ;;
    *)
        log_message "Unknown action: $ACTION" "Error"
        show_help
        exit 1
        ;;
esac
