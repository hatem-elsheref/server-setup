#!/bin/bash

###############################################################################
# HPanel - Deploy Script
# 
# Purpose: Deploy project from Git with zero-downtime
# Usage: sudo ./deploy.sh PROJECT_NAME [GIT_REPO] [BRANCH_OR_TAG]
# 
# Examples:
#   ./deploy.sh myapp
#   ./deploy.sh myapp https://github.com/user/repo.git
#   ./deploy.sh myapp https://github.com/user/repo.git main
#   ./deploy.sh myapp https://github.com/user/repo.git v1.2.3
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

get_project_backend_type() {
    local project_dir=$1
    
    # Check for Laravel
    if [ -f "$project_dir/current/artisan" ]; then
        echo "laravel"
        return 0
    fi
    
    # Check for Node.js (package.json with start script)
    if [ -f "$project_dir/current/package.json" ]; then
        if grep -q '"start"' "$project_dir/current/package.json" 2>/dev/null; then
            echo "node"
            return 0
        fi
    fi
    
    # Check for React (build folder or public/index.html)
    if [ -d "$project_dir/current/build" ] || [ -f "$project_dir/current/public/index.html" ]; then
        echo "react"
        return 0
    fi
    
    # Default: try to detect from existing .env or config
    if [ -f "$project_dir/shared/.env" ]; then
        if grep -q "APP_NAME" "$project_dir/shared/.env" 2>/dev/null; then
            echo "laravel"
            return 0
        fi
    fi
    
    echo "unknown"
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
        log_info "Create it first: ./bin/create-project.sh"
        exit 1
    fi
    
    PROJECT_DIR="$project_dir"
    PROJECT_USER=$(get_project_user "$project_name")
    
    if [ -z "$PROJECT_USER" ]; then
        log_error "Could not find user for project '$project_name'"
        exit 1
    fi
    
    log_success "Project validated: $project_name (user: $PROJECT_USER)"
}

###############################################################################
# Get Git Repository
###############################################################################

get_git_repo() {
    local project_dir=$1
    local git_repo=$2
    
    # If repo provided, use it
    if [ -n "$git_repo" ]; then
        echo "$git_repo"
        return 0
    fi
    
    # Check if .git exists in current
    if [ -d "$project_dir/current/.git" ]; then
        local remote_url=$(cd "$project_dir/current" && git remote get-url origin 2>/dev/null || echo "")
        if [ -n "$remote_url" ]; then
            echo "$remote_url"
            return 0
        fi
    fi
    
    # Check shared/.env for GIT_REPO
    if [ -f "$project_dir/shared/.env" ]; then
        local repo=$(grep "^GIT_REPO=" "$project_dir/shared/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -n "$repo" ]; then
            echo "$repo"
            return 0
        fi
    fi
    
    log_error "Git repository not found. Please provide it:"
    log_info "  ./deploy.sh $PROJECT_NAME https://github.com/user/repo.git"
    exit 1
}

###############################################################################
# Create Release Folder
###############################################################################

create_release_folder() {
    local project_dir=$1
    local releases_dir="$project_dir/releases"
    
    # Generate release name (timestamp or git tag)
    local release_name
    if [ -n "${BRANCH_OR_TAG:-}" ] && [[ "$BRANCH_OR_TAG" =~ ^v?[0-9] ]]; then
        # It's a tag
        release_name="${BRANCH_OR_TAG//\//-}"
    else
        # Use timestamp
        release_name="$(date +%Y%m%d%H%M%S)"
    fi
    
    local release_dir="$releases_dir/$release_name"
    
    # Create releases directory if it doesn't exist
    mkdir -p "$releases_dir"
    
    # Create release folder
    mkdir -p "$release_dir"
    
    RELEASE_DIR="$release_dir"
    RELEASE_NAME="$release_name"
    
    log_info "Creating release: $release_name"
}

###############################################################################
# Clone/Pull Code
###############################################################################

clone_code() {
    local git_repo=$1
    local release_dir=$2
    local branch_or_tag=${3:-}
    
    log_info "Cloning code from Git..."
    
    # Clone to release folder
    if [ -n "$branch_or_tag" ]; then
        log_info "Checking out: $branch_or_tag"
        git clone --depth 1 --branch "$branch_or_tag" "$git_repo" "$release_dir" 2>&1 | grep -v "Cloning into" || true
    else
        git clone --depth 1 "$git_repo" "$release_dir" 2>&1 | grep -v "Cloning into" || true
    fi
    
    # Set ownership
    chown -R "$PROJECT_USER:$PROJECT_USER" "$release_dir"
    
    log_success "Code cloned"
}

###############################################################################
# Install Dependencies (Laravel)
###############################################################################

install_laravel_dependencies() {
    local release_dir=$1
    
    log_info "Installing Laravel dependencies (Composer)..."
    
    # Run as project user
    sudo -u "$PROJECT_USER" bash <<EOF
cd "$release_dir"
composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist
EOF
    
    log_success "Dependencies installed"
}

###############################################################################
# Install Dependencies (Node.js)
###############################################################################

install_node_dependencies() {
    local release_dir=$1
    
    log_info "Installing Node.js dependencies (npm)..."
    
    # Run as project user
    sudo -u "$PROJECT_USER" bash <<EOF
cd "$release_dir"
npm install --production --no-audit --no-fund
EOF
    
    log_success "Dependencies installed"
}

###############################################################################
# Build React App
###############################################################################

build_react_app() {
    local release_dir=$1
    
    log_info "Building React application..."
    
    # Run as project user
    sudo -u "$PROJECT_USER" bash <<EOF
cd "$release_dir"
npm install --no-audit --no-fund
npm run build
EOF
    
    log_success "React app built"
}

###############################################################################
# Link Shared Files
###############################################################################

link_shared_files() {
    local release_dir=$1
    local shared_dir="$PROJECT_DIR/shared"
    local backend_type=$2
    
    log_info "Linking shared files..."
    
    # Link .env
    if [ -f "$shared_dir/.env" ]; then
        ln -sfn "$shared_dir/.env" "$release_dir/.env"
        log_info "Linked .env"
    fi
    
    # Laravel specific: link storage
    if [ "$backend_type" == "laravel" ]; then
        # Link storage directory
        if [ -d "$shared_dir/storage" ]; then
            # Remove storage from release if it exists
            [ -d "$release_dir/storage" ] && rm -rf "$release_dir/storage"
            ln -sfn "$shared_dir/storage" "$release_dir/storage"
            log_info "Linked storage directory"
        else
            # Create storage if it doesn't exist
            mkdir -p "$shared_dir/storage"
            mkdir -p "$shared_dir/storage/app"
            mkdir -p "$shared_dir/storage/framework"
            mkdir -p "$shared_dir/storage/framework/cache"
            mkdir -p "$shared_dir/storage/framework/sessions"
            mkdir -p "$shared_dir/storage/framework/views"
            mkdir -p "$shared_dir/storage/logs"
            chown -R "$PROJECT_USER:$PROJECT_USER" "$shared_dir/storage"
            ln -sfn "$shared_dir/storage" "$release_dir/storage"
            log_info "Created and linked storage directory"
        fi
        
        # Link bootstrap/cache
        if [ -d "$shared_dir/bootstrap/cache" ]; then
            [ -d "$release_dir/bootstrap/cache" ] && rm -rf "$release_dir/bootstrap/cache"
            ln -sfn "$shared_dir/bootstrap/cache" "$release_dir/bootstrap/cache"
        fi
    fi
    
    log_success "Shared files linked"
}

###############################################################################
# Laravel Post-Deploy Steps
###############################################################################

laravel_post_deploy() {
    local release_dir=$1
    
    log_info "Running Laravel post-deploy steps..."
    
    # Run as project user
    sudo -u "$PROJECT_USER" bash <<EOF
cd "$release_dir"
php artisan config:cache
php artisan route:cache
php artisan view:cache
EOF
    
    log_success "Laravel caches cleared and rebuilt"
}

###############################################################################
# Run Migrations (Laravel)
###############################################################################

run_migrations() {
    local release_dir=$1
    
    log_info "Running database migrations..."
    
    # Ask for confirmation
    read -p "Run database migrations? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Skipping migrations"
        return 0
    fi
    
    # Run as project user
    sudo -u "$PROJECT_USER" bash <<EOF
cd "$release_dir"
php artisan migrate --force
EOF
    
    log_success "Migrations completed"
}

###############################################################################
# Switch to New Release (Atomic)
###############################################################################

switch_to_release() {
    local release_dir=$1
    local project_dir=$2
    
    log_info "Switching to new release (atomic operation)..."
    
    # Update symlink atomically
    ln -sfn "$release_dir" "$project_dir/current"
    
    log_success "Switched to new release (zero downtime!)"
}

###############################################################################
# Restart Services
###############################################################################

restart_services() {
    local backend_type=$1
    local project_name=$2
    
    log_info "Restarting services..."
    
    case "$backend_type" in
        laravel)
            # Reload PHP-FPM (graceful, keeps connections)
            # Get PHP version from .env or default to 8.2
            local php_version="8.2"
            if [ -f "$PROJECT_DIR/shared/.env" ]; then
                # Try to detect from existing setup
                local nginx_config=$(find /infra/services/nginx/sites-enabled -name "*.conf" -exec grep -l "$project_name" {} \; | head -1)
                if [ -n "$nginx_config" ]; then
                    local detected=$(grep "php.*-fpm.sock" "$nginx_config" | sed 's/.*php\([0-9.]*\)-fpm.*/\1/' | head -1)
                    [ -n "$detected" ] && php_version="$detected"
                fi
            fi
            systemctl reload "php${php_version}-fpm" 2>/dev/null || log_warning "Could not reload PHP-FPM"
            log_success "PHP-FPM reloaded"
            ;;
            
        node)
            # Restart PM2 process
            if command -v pm2 &> /dev/null; then
                pm2 restart "$project_name" 2>/dev/null || pm2 start "$PROJECT_DIR/current" --name "$project_name" 2>/dev/null || log_warning "PM2 restart failed"
                log_success "Node.js process restarted"
            else
                log_warning "PM2 not found, please restart Node.js manually"
            fi
            ;;
            
        react)
            # No restart needed for static files
            log_info "No service restart needed (static files)"
            ;;
    esac
}

###############################################################################
# Cleanup Old Releases
###############################################################################

cleanup_old_releases() {
    local releases_dir=$1
    local keep_releases=5
    
    log_info "Cleaning up old releases (keeping last $keep_releases)..."
    
    # Get list of releases, sorted by name (newest first)
    local releases=($(ls -1t "$releases_dir" 2>/dev/null | head -n $keep_releases))
    local all_releases=($(ls -1t "$releases_dir" 2>/dev/null))
    
    # Delete releases not in the keep list
    for release in "${all_releases[@]}"; do
        local keep=false
        for keep_release in "${releases[@]}"; do
            if [ "$release" == "$keep_release" ]; then
                keep=true
                break
            fi
        done
        
        if [ "$keep" == false ]; then
            log_info "Deleting old release: $release"
            rm -rf "$releases_dir/$release"
        fi
    done
    
    log_success "Cleanup completed"
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Parse arguments
    PROJECT_NAME=${1:-}
    GIT_REPO=${2:-}
    BRANCH_OR_TAG=${3:-}
    
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Usage: ./deploy.sh PROJECT_NAME [GIT_REPO] [BRANCH_OR_TAG]"
        exit 1
    fi
    
    check_root
    
    log_info "=========================================="
    log_info "HPanel - Deploy Project"
    log_info "=========================================="
    log_info ""
    
    # Validate project
    validate_project "$PROJECT_NAME"
    
    # Get Git repository
    GIT_REPO=$(get_git_repo "$PROJECT_DIR" "$GIT_REPO")
    log_info "Git repository: $GIT_REPO"
    
    # Detect backend type
    BACKEND_TYPE=$(get_project_backend_type "$PROJECT_DIR")
    if [ "$BACKEND_TYPE" == "unknown" ]; then
        log_warning "Could not detect backend type, assuming Laravel"
        BACKEND_TYPE="laravel"
    fi
    log_info "Backend type: $BACKEND_TYPE"
    log_info ""
    
    # Create release folder
    create_release_folder "$PROJECT_DIR"
    
    # Clone code
    clone_code "$GIT_REPO" "$RELEASE_DIR" "$BRANCH_OR_TAG"
    
    # Install dependencies based on backend type
    case "$BACKEND_TYPE" in
        laravel)
            install_laravel_dependencies "$RELEASE_DIR"
            link_shared_files "$RELEASE_DIR" "$BACKEND_TYPE"
            laravel_post_deploy "$RELEASE_DIR"
            run_migrations "$RELEASE_DIR"
            ;;
            
        node)
            install_node_dependencies "$RELEASE_DIR"
            link_shared_files "$RELEASE_DIR" "$BACKEND_TYPE"
            ;;
            
        react)
            build_react_app "$RELEASE_DIR"
            # For React, point to build folder
            if [ -d "$RELEASE_DIR/build" ]; then
                RELEASE_DIR="$RELEASE_DIR/build"
            elif [ -d "$RELEASE_DIR/dist" ]; then
                RELEASE_DIR="$RELEASE_DIR/dist"
            fi
            ;;
    esac
    
    # Set proper ownership
    chown -R "$PROJECT_USER:$PROJECT_USER" "$RELEASE_DIR"
    
    # Switch to new release (atomic)
    switch_to_release "$RELEASE_DIR" "$PROJECT_DIR"
    
    # Restart services
    restart_services "$BACKEND_TYPE" "$PROJECT_NAME"
    
    # Cleanup old releases
    cleanup_old_releases "$PROJECT_DIR/releases"
    
    log_info ""
    log_success "=========================================="
    log_success "Deployment Complete!"
    log_success "=========================================="
    log_info ""
    log_info "Project: $PROJECT_NAME"
    log_info "Release: $RELEASE_NAME"
    log_info "Backend: $BACKEND_TYPE"
    log_info ""
    log_success "Your application is now live with zero downtime!"
    log_info ""
}

# Run main function
main "$@"
