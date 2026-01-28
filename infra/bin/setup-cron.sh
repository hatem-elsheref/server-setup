#!/bin/bash

###############################################################################
# HPanel - Setup Cron (Laravel Scheduler) Script
# 
# Purpose: Set up Laravel scheduler via cron
# Usage: sudo ./setup-cron.sh PROJECT_NAME
# 
# Example:
#   ./setup-cron.sh myapp
###############################################################################

set -e
set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$INFRA_DIR/config.env"
PROJECTS_DIR="$INFRA_DIR/projects"
USERS_MAP="$INFRA_DIR/users.map"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: config.env not found${NC}"
    exit 1
fi

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root or with sudo"
        exit 1
    fi
}

get_project_user() {
    local project_name=$1
    if [ -f "$USERS_MAP" ]; then
        while IFS=: read -r proj user uid; do
            if [ "$proj" == "$project_name" ]; then
                echo "$user"
                return 0
            fi
        done < <(grep -v "^#" "$USERS_MAP" | grep -v "^$")
    fi
    return 1
}

###############################################################################
# Validate Project
###############################################################################

validate_project() {
    local project_name=$1
    
    if [ -z "$project_name" ]; then
        log_error "Project name is required"
        exit 1
    fi
    
    local project_dir="$PROJECTS_DIR/$project_name"
    
    if [ ! -d "$project_dir" ]; then
        log_error "Project '$project_name' does not exist"
        exit 1
    fi
    
    PROJECT_DIR="$project_dir"
    PROJECT_USER=$(get_project_user "$project_name")
    
    if [ -z "$PROJECT_USER" ]; then
        log_error "Could not find user for project '$project_name'"
        exit 1
    fi
    
    # Check if Laravel (has artisan)
    if [ ! -f "$project_dir/current/artisan" ]; then
        log_error "Project does not appear to be Laravel (artisan not found)"
        log_info "This script is for Laravel scheduler only"
        exit 1
    fi
    
    log_success "Project validated: $project_name (user: $PROJECT_USER)"
}

###############################################################################
# Setup Cron Entry
###############################################################################

setup_cron() {
    local project_name=$1
    local project_dir=$2
    local project_user=$3
    
    log_info "Setting up Laravel scheduler cron entry..."
    
    local cron_entry="* * * * * cd $project_dir/current && php artisan schedule:run >> /dev/null 2>&1"
    local cron_comment="# HPanel Laravel Scheduler for $project_name"
    
    # Check if cron entry already exists
    if crontab -u "$project_user" -l 2>/dev/null | grep -q "artisan schedule:run"; then
        log_warning "Cron entry already exists for $project_user"
        read -p "Update existing entry? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping cron setup"
            return 0
        fi
        # Remove old entry
        crontab -u "$project_user" -l 2>/dev/null | grep -v "artisan schedule:run" | crontab -u "$project_user" - 2>/dev/null || true
    fi
    
    # Add new cron entry
    (crontab -u "$project_user" -l 2>/dev/null; echo "$cron_comment"; echo "$cron_entry") | crontab -u "$project_user" -
    
    log_success "Cron entry added"
}

###############################################################################
# Verify Setup
###############################################################################

verify_setup() {
    local project_user=$1
    
    log_info "Verifying cron setup..."
    
    # Check if cron entry exists
    if crontab -u "$project_user" -l 2>/dev/null | grep -q "artisan schedule:run"; then
        log_success "Cron entry verified"
        log_info ""
        log_info "Current cron entries for $project_user:"
        crontab -u "$project_user" -l 2>/dev/null | grep -A 1 "artisan schedule:run" || true
    else
        log_error "Cron entry not found"
        exit 1
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Parse arguments
    PROJECT_NAME=${1:-}
    
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Usage: ./setup-cron.sh PROJECT_NAME"
        exit 1
    fi
    
    check_root
    
    log_info "=========================================="
    log_info "HPanel - Setup Laravel Scheduler"
    log_info "=========================================="
    log_info ""
    
    # Validate project
    validate_project "$PROJECT_NAME"
    
    # Setup cron
    setup_cron "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_USER"
    
    # Verify
    verify_setup "$PROJECT_USER"
    
    log_info ""
    log_success "=========================================="
    log_success "Cron Setup Complete!"
    log_success "=========================================="
    log_info ""
    log_info "Project: $PROJECT_NAME"
    log_info "User: $PROJECT_USER"
    log_info ""
    log_info "Laravel scheduler will run every minute"
    log_info "Define scheduled tasks in: app/Console/Kernel.php"
    log_info ""
    log_info "Useful commands:"
    log_info "  crontab -u $PROJECT_USER -l          # View cron entries"
    log_info "  php artisan schedule:list            # List scheduled tasks"
    log_info "  php artisan schedule:run             # Run scheduler manually"
    log_info ""
}

# Run main function
main "$@"
