#!/bin/bash

###############################################################################
# HPanel - Setup Supervisor Script
# 
# Purpose: Configure Supervisor for background processes (queues, workers)
# Usage: sudo ./setup-supervisor.sh PROJECT_NAME TYPE [OPTIONS]
# 
# Types:
#   queue  - Laravel queue worker
#   node   - Node.js worker (Socket.IO, etc.)
#   custom - Custom command
# 
# Examples:
#   ./setup-supervisor.sh myapp queue
#   ./setup-supervisor.sh myapp queue --workers=4
#   ./setup-supervisor.sh myapp node
#   ./setup-supervisor.sh myapp custom "php artisan custom:command"
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
TEMPLATES_DIR="$INFRA_DIR/templates"

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
    
    # Check if current symlink exists
    if [ ! -L "$project_dir/current" ]; then
        log_error "Project not deployed yet. Run: ./bin/deploy.sh $project_name"
        exit 1
    fi
    
    log_success "Project validated: $project_name (user: $PROJECT_USER)"
}

###############################################################################
# Create Laravel Queue Config
###############################################################################

create_laravel_queue_config() {
    local project_name=$1
    local project_dir=$2
    local project_user=$3
    local num_workers=${4:-2}
    
    local config_file="/etc/supervisor/conf.d/${project_name}_queue.conf"
    local log_dir="$INFRA_DIR/logs/projects/$project_name"
    mkdir -p "$log_dir"
    
    log_info "Creating Laravel queue worker config..."
    
    cat > "$config_file" <<EOF
[program:${project_name}_queue]
process_name=%(program_name)s_%(process_num)02d
command=php $project_dir/current/artisan queue:work --sleep=3 --tries=3 --max-time=3600
directory=$project_dir/current
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=$project_user
numprocs=$num_workers
redirect_stderr=true
stdout_logfile=$log_dir/queue.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stopwaitsecs=3600
EOF
    
    chmod 644 "$config_file"
    log_success "Laravel queue config created"
}

###############################################################################
# Create Node.js Worker Config
###############################################################################

create_node_worker_config() {
    local project_name=$1
    local project_dir=$2
    local project_user=$3
    
    local config_file="/etc/supervisor/conf.d/${project_name}_node.conf"
    local log_dir="$INFRA_DIR/logs/projects/$project_name"
    mkdir -p "$log_dir"
    
    log_info "Creating Node.js worker config..."
    
    # Detect start command
    local start_cmd="node server.js"
    if [ -f "$project_dir/current/package.json" ]; then
        if grep -q '"start"' "$project_dir/current/package.json"; then
            start_cmd="npm start"
        fi
    fi
    
    cat > "$config_file" <<EOF
[program:${project_name}_node]
command=$start_cmd
directory=$project_dir/current
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=$project_user
environment=NODE_ENV="production"
redirect_stderr=true
stdout_logfile=$log_dir/node.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stopwaitsecs=10
EOF
    
    chmod 644 "$config_file"
    log_success "Node.js worker config created"
}

###############################################################################
# Create Custom Worker Config
###############################################################################

create_custom_worker_config() {
    local project_name=$1
    local project_dir=$2
    local project_user=$3
    local command=$4
    local worker_name=${5:-custom}
    
    local config_file="/etc/supervisor/conf.d/${project_name}_${worker_name}.conf"
    local log_dir="$INFRA_DIR/logs/projects/$project_name"
    mkdir -p "$log_dir"
    
    log_info "Creating custom worker config..."
    
    cat > "$config_file" <<EOF
[program:${project_name}_${worker_name}]
command=$command
directory=$project_dir/current
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=$project_user
redirect_stderr=true
stdout_logfile=$log_dir/${worker_name}.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
EOF
    
    chmod 644 "$config_file"
    log_success "Custom worker config created"
}

###############################################################################
# Reload Supervisor
###############################################################################

reload_supervisor() {
    log_info "Reloading Supervisor..."
    
    supervisorctl reread > /dev/null 2>&1
    supervisorctl update > /dev/null 2>&1
    
    log_success "Supervisor reloaded"
}

###############################################################################
# Start Workers
###############################################################################

start_workers() {
    local project_name=$1
    local worker_type=$2
    
    log_info "Starting workers..."
    
    case "$worker_type" in
        queue)
            supervisorctl start "${project_name}_queue:*" > /dev/null 2>&1 || true
            log_success "Laravel queue workers started"
            ;;
        node)
            supervisorctl start "${project_name}_node" > /dev/null 2>&1 || true
            log_success "Node.js worker started"
            ;;
        custom)
            # Will be started automatically
            log_success "Custom worker will start automatically"
            ;;
    esac
    
    # Show status
    log_info ""
    log_info "Worker status:"
    supervisorctl status | grep "^${project_name}_" || true
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Parse arguments
    PROJECT_NAME=${1:-}
    WORKER_TYPE=${2:-}
    EXTRA_ARGS=${3:-}
    
    if [ -z "$PROJECT_NAME" ] || [ -z "$WORKER_TYPE" ]; then
        log_error "Usage: ./setup-supervisor.sh PROJECT_NAME TYPE [OPTIONS]"
        log_info ""
        log_info "Types:"
        log_info "  queue  - Laravel queue worker"
        log_info "  node   - Node.js worker"
        log_info "  custom - Custom command (requires command as 3rd arg)"
        log_info ""
        log_info "Examples:"
        log_info "  ./setup-supervisor.sh myapp queue"
        log_info "  ./setup-supervisor.sh myapp queue --workers=4"
        log_info "  ./setup-supervisor.sh myapp node"
        log_info "  ./setup-supervisor.sh myapp custom 'php artisan custom:command'"
        exit 1
    fi
    
    check_root
    
    log_info "=========================================="
    log_info "HPanel - Setup Supervisor"
    log_info "=========================================="
    log_info ""
    
    # Validate project
    validate_project "$PROJECT_NAME"
    
    # Parse extra args for queue workers
    local num_workers=2
    if [[ "$EXTRA_ARGS" =~ --workers=([0-9]+) ]]; then
        num_workers="${BASH_REMATCH[1]}"
    fi
    
    # Create config based on type
    case "$WORKER_TYPE" in
        queue)
            create_laravel_queue_config "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_USER" "$num_workers"
            ;;
        node)
            create_node_worker_config "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_USER"
            ;;
        custom)
            if [ -z "$EXTRA_ARGS" ]; then
                log_error "Custom worker requires a command"
                log_info "Example: ./setup-supervisor.sh myapp custom 'php artisan custom:command'"
                exit 1
            fi
            create_custom_worker_config "$PROJECT_NAME" "$PROJECT_DIR" "$PROJECT_USER" "$EXTRA_ARGS"
            ;;
        *)
            log_error "Invalid worker type: $WORKER_TYPE"
            log_info "Valid types: queue, node, custom"
            exit 1
            ;;
    esac
    
    # Reload supervisor
    reload_supervisor
    
    # Start workers
    start_workers "$PROJECT_NAME" "$WORKER_TYPE"
    
    log_info ""
    log_success "=========================================="
    log_success "Supervisor Setup Complete!"
    log_success "=========================================="
    log_info ""
    log_info "Project: $PROJECT_NAME"
    log_info "Worker type: $WORKER_TYPE"
    [ "$WORKER_TYPE" == "queue" ] && log_info "Workers: $num_workers"
    log_info ""
    log_info "Useful commands:"
    log_info "  supervisorctl status                    # View all workers"
    log_info "  supervisorctl restart ${PROJECT_NAME}_*  # Restart workers"
    log_info "  tail -f /infra/logs/projects/$PROJECT_NAME/*.log  # View logs"
    log_info ""
}

# Run main function
main "$@"
