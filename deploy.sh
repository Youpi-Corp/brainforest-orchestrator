#!/bin/bash

# Production deployment script for Brainforest
set -e

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env.prod"
BACKUP_DIR="./backups"
LOG_FILE="./logs/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if environment file exists
check_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file $ENV_FILE not found!"
        info "Copy .env.prod.example to .env.prod and configure it"
        exit 1
    fi
}

# Backup database
backup_database() {
    log "Creating database backup..."
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql"
    
    if docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$BACKUP_FILE"; then
        log "Database backup created: $BACKUP_FILE"
        
        # Compress backup
        gzip "$BACKUP_FILE"
        log "Backup compressed: $BACKUP_FILE.gz"
        
        # Clean old backups (keep last 30 days)
        find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +30 -delete
        log "Old backups cleaned"
    else
        error "Database backup failed"
        return 1
    fi
}

# Deploy application
deploy() {
    log "Starting production deployment..."
    
    # Pull latest images
    info "Pulling latest images..."
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
    
    # Build and start services
    info "Building and starting services..."
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
    
    # Wait for services to be healthy
    info "Waiting for services to be healthy..."
    sleep 30
    
    # Check service health
    if docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps | grep -q "unhealthy"; then
        error "Some services are unhealthy!"
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
        return 1
    fi
    
    log "Deployment completed successfully!"
}

# Rollback to previous version
rollback() {
    warning "Rolling back to previous version..."
    
    # Stop current services
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
    
    # Restore from backup
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_*.sql.gz | head -n1)
    if [ -n "$LATEST_BACKUP" ]; then
        log "Restoring database from: $LATEST_BACKUP"
        gunzip -c "$LATEST_BACKUP" | docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    fi
    
    # Start services with previous image
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    
    log "Rollback completed"
}

# Show logs
show_logs() {
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f "${2:-}"
}

# Show status
show_status() {
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
    
    echo -e "\n${BLUE}=== Resource Usage ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

# Main command handling
case "${1:-}" in
    "deploy")
        check_env_file
        backup_database
        deploy
        ;;
    "rollback")
        check_env_file
        rollback
        ;;
    "backup")
        check_env_file
        backup_database
        ;;
    "logs")
        check_env_file
        show_logs "$@"
        ;;
    "status")
        check_env_file
        show_status
        ;;
    "stop")
        check_env_file
        log "Stopping services..."
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
        ;;
    "restart")
        check_env_file
        log "Restarting services..."
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" restart
        ;;
    *)
        echo "Usage: $0 {deploy|rollback|backup|logs|status|stop|restart}"
        echo ""
        echo "Commands:"
        echo "  deploy   - Deploy the application to production"
        echo "  rollback - Rollback to previous version"
        echo "  backup   - Create database backup"
        echo "  logs     - Show application logs"
        echo "  status   - Show service status and resource usage"
        echo "  stop     - Stop all services"
        echo "  restart  - Restart all services"
        exit 1
        ;;
esac
