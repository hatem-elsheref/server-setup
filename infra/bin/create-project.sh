#!/bin/bash

###############################################################################
# HPanel - Create New Project Script
# 
# Purpose: Interactive script to create a new project
# Usage: sudo ./create-project.sh
# 
# This script:
# - Asks questions about the project
# - Creates folder structure
# - Creates Linux user
# - Creates database
# - Generates Nginx config
# - Sets up .env file
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
PORTS_MAP="$INFRA_DIR/ports.map"
USERS_MAP="$INFRA_DIR/users.map"
PROJECTS_DIR="$INFRA_DIR/projects"
TEMPLATES_DIR="$INFRA_DIR/templates"
SERVICES_DIR="$INFRA_DIR/services"

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

validate_project_name() {
    local name=$1
    if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Project name must be lowercase, alphanumeric, and can contain hyphens"
        return 1
    fi
    if [ -d "$PROJECTS_DIR/$name" ]; then
        log_error "Project '$name' already exists"
        return 1
    fi
    return 0
}

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format"
        return 1
    fi
    # Check if domain already in use
    if [ -f "$SERVICES_DIR/nginx/sites-available/${domain}.conf" ]; then
        log_error "Domain '$domain' is already in use"
        return 1
    fi
    return 0
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

get_next_uid() {
    local start_uid=${PHP_FPM_POOL_START_UID:-10000}
    local max_uid=0
    
    if [ -f "$USERS_MAP" ]; then
        while IFS=: read -r project user uid; do
            if [[ "$uid" =~ ^[0-9]+$ ]] && [ "$uid" -gt "$max_uid" ]; then
                max_uid=$uid
            fi
        done < <(grep -v "^#" "$USERS_MAP" | grep -v "^$")
    fi
    
    if [ "$max_uid" -ge "$start_uid" ]; then
        echo $((max_uid + 1))
    else
        echo $start_uid
    fi
}

get_next_node_port() {
    local start_port=${NODE_PORT_START:-8000}
    local max_port=$((start_port - 1))
    
    if [ -f "$PORTS_MAP" ]; then
        while IFS=: read -r project port type; do
            if [[ "$type" == "node" ]] && [[ "$port" =~ ^[0-9]+$ ]]; then
                if [ "$port" -gt "$max_port" ]; then
                    max_port=$port
                fi
            fi
        done < <(grep -v "^#" "$PORTS_MAP" | grep -v "^$")
    fi
    
    if [ "$max_port" -ge "$start_port" ]; then
        echo $((max_port + 1))
    else
        echo $start_port
    fi
}

###############################################################################
# Interactive Questions
###############################################################################

ask_questions() {
    log_info "=== HPanel - Create New Project ==="
    log_info ""
    
    # Project name
    while true; do
        read -p "Project name (lowercase, alphanumeric, hyphens only): " PROJECT_NAME
        if validate_project_name "$PROJECT_NAME"; then
            break
        fi
    done
    
    # Domain
    while true; do
        read -p "Domain/subdomain (e.g., ${PROJECT_NAME}.example.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        fi
    done
    
    # Backend type
    while true; do
        read -p "Backend type [laravel/node/react]: " BACKEND_TYPE
        BACKEND_TYPE=$(echo "$BACKEND_TYPE" | tr '[:upper:]' '[:lower:]')
        if [[ "$BACKEND_TYPE" =~ ^(laravel|node|react)$ ]]; then
            break
        fi
        log_error "Invalid backend type. Choose: laravel, node, or react"
    done
    
    # Database type
    while true; do
        read -p "Database type [mysql/postgres/mongodb/none]: " DB_TYPE
        DB_TYPE=$(echo "$DB_TYPE" | tr '[:upper:]' '[:lower:]')
        if [[ "$DB_TYPE" =~ ^(mysql|postgres|mongodb|none)$ ]]; then
            break
        fi
        log_error "Invalid database type. Choose: mysql, postgres, mongodb, or none"
    done
    
    # PHP version (if Laravel)
    if [ "$BACKEND_TYPE" == "laravel" ]; then
        while true; do
            read -p "PHP version [7.4/8.0/8.1/8.2/8.3]: " PHP_VERSION
            if [[ "$PHP_VERSION" =~ ^(7\.4|8\.0|8\.1|8\.2|8\.3)$ ]]; then
                break
            fi
            log_error "Invalid PHP version. Choose: 7.4, 8.0, 8.1, 8.2, or 8.3"
        done
    else
        PHP_VERSION=""
    fi
    
    # Git repository (optional)
    read -p "Git repository URL (optional, press Enter to skip): " GIT_REPO
    
    log_info ""
    log_info "Summary:"
    log_info "  Project: $PROJECT_NAME"
    log_info "  Domain: $DOMAIN"
    log_info "  Backend: $BACKEND_TYPE"
    log_info "  Database: $DB_TYPE"
    [ -n "$PHP_VERSION" ] && log_info "  PHP: $PHP_VERSION"
    [ -n "$GIT_REPO" ] && log_info "  Git: $GIT_REPO"
    log_info ""
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled."
        exit 0
    fi
}

###############################################################################
# Create Project Structure
###############################################################################

create_project_structure() {
    log_info "Creating project structure..."
    
    local project_dir="$PROJECTS_DIR/$PROJECT_NAME"
    
    # Create directories
    mkdir -p "$project_dir/releases"
    mkdir -p "$project_dir/shared/storage"
    mkdir -p "$project_dir/shared/logs"
    mkdir -p "$INFRA_DIR/logs/projects/$PROJECT_NAME"
    
    # Create current symlink (will point to first release later)
    ln -sfn "$project_dir/releases" "$project_dir/current"
    
    log_success "Project structure created"
}

###############################################################################
# Create Linux User
###############################################################################

create_linux_user() {
    log_info "Creating Linux user..."
    
    local username="${PROJECT_NAME}_user"
    local uid=$(get_next_uid)
    local project_dir="$PROJECTS_DIR/$PROJECT_NAME"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        log_warning "User '$username' already exists, skipping creation"
    else
        # Create user with home directory
        useradd -r -u "$uid" -d "$project_dir" -s /bin/bash "$username"
        
        # Set password (random, user will use SSH keys)
        echo "$username:$(generate_password)" | chpasswd
        
        # Add to www-data group (for web server access)
        usermod -aG www-data "$username"
        
        log_success "User '$username' created (UID: $uid)"
    fi
    
    # Set ownership
    chown -R "$username:$username" "$project_dir"
    chmod 755 "$project_dir"
    
    # Update users.map
    echo "$PROJECT_NAME:$username:$uid" >> "$USERS_MAP"
    
    PROJECT_USER="$username"
    PROJECT_UID="$uid"
}

###############################################################################
# Create Database
###############################################################################

create_database() {
    if [ "$DB_TYPE" == "none" ]; then
        log_info "Skipping database creation (none selected)"
        DB_NAME=""
        DB_USER=""
        DB_PASSWORD=""
        return
    fi
    
    log_info "Creating database..."
    
    DB_NAME="${PROJECT_NAME}_db"
    DB_USER="${PROJECT_NAME}_user"
    DB_PASSWORD=$(generate_password)
    
    case "$DB_TYPE" in
        mysql)
            # Get MySQL root password
            local root_pass=""
            if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                root_pass="$MYSQL_ROOT_PASSWORD"
            else
                log_error "MySQL root password not set in config.env"
                exit 1
            fi
            
            # Create database and user
            mysql -u root -p"$root_pass" <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
            log_success "MySQL database '$DB_NAME' created"
            ;;
            
        postgres)
            # Create database and user
            sudo -u postgres psql <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
GRANT ALL ON SCHEMA public TO ${DB_USER};
EOF
            log_success "PostgreSQL database '$DB_NAME' created"
            ;;
            
        mongodb)
            # Create database and user
            mongosh <<EOF
use ${DB_NAME}
db.createUser({
  user: "${DB_USER}",
  pwd: "${DB_PASSWORD}",
  roles: [{ role: "readWrite", db: "${DB_NAME}" }]
})
EOF
            log_success "MongoDB database '$DB_NAME' created"
            ;;
    esac
}

###############################################################################
# Generate Nginx Config
###############################################################################

generate_nginx_config() {
    log_info "Generating Nginx configuration..."
    
    local template=""
    local project_dir="$PROJECTS_DIR/$PROJECT_NAME"
    
    # Select template based on backend type
    case "$BACKEND_TYPE" in
        laravel)
            template="$TEMPLATES_DIR/nginx/laravel.conf"
            ;;
        node)
            template="$TEMPLATES_DIR/nginx/nodejs.conf"
            ;;
        react)
            template="$TEMPLATES_DIR/nginx/react.conf"
            ;;
    esac
    
    # Check if template exists, if not create basic one
    if [ ! -f "$template" ]; then
        log_warning "Template not found, creating basic config..."
        create_basic_nginx_template "$template" "$BACKEND_TYPE"
    fi
    
    # Read template and replace placeholders
    local config_file="$SERVICES_DIR/nginx/sites-available/${DOMAIN}.conf"
    
    sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
        -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
        -e "s|{{PROJECT_ROOT}}|$project_dir|g" \
        -e "s|{{PHP_VERSION}}|$PHP_VERSION|g" \
        -e "s|{{NODE_PORT}}|${NODE_PORT:-}|g" \
        "$template" > "$config_file"
    
    # Create symlink to sites-enabled
    ln -sfn "$config_file" "$SERVICES_DIR/nginx/sites-enabled/${DOMAIN}.conf"
    
    # Test Nginx config
    if nginx -t > /dev/null 2>&1; then
        systemctl reload nginx
        log_success "Nginx configuration created and enabled"
    else
        log_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi
}

create_basic_nginx_template() {
    local template=$1
    local backend_type=$2
    
    mkdir -p "$(dirname "$template")"
    
    case "$backend_type" in
        laravel)
            cat > "$template" <<'EOF'
server {
    listen 80;
    server_name {{DOMAIN}};
    root {{PROJECT_ROOT}}/current/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
            ;;
        node)
            cat > "$template" <<'EOF'
server {
    listen 80;
    server_name {{DOMAIN}};

    location / {
        proxy_pass http://127.0.0.1:{{NODE_PORT}};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
            ;;
        react)
            cat > "$template" <<'EOF'
server {
    listen 80;
    server_name {{DOMAIN}};
    root {{PROJECT_ROOT}}/current;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
            ;;
    esac
}

###############################################################################
# Allocate Port (for Node.js)
###############################################################################

allocate_port() {
    if [ "$BACKEND_TYPE" == "node" ]; then
        NODE_PORT=$(get_next_node_port)
        echo "$PROJECT_NAME:$NODE_PORT:node" >> "$PORTS_MAP"
        log_info "Allocated port $NODE_PORT for Node.js"
    fi
}

###############################################################################
# Create .env File
###############################################################################

create_env_file() {
    log_info "Creating .env file..."
    
    local env_file="$PROJECTS_DIR/$PROJECT_NAME/shared/.env"
    local template=""
    
    # Select template
    case "$BACKEND_TYPE" in
        laravel)
            template="$TEMPLATES_DIR/env/laravel.env.example"
            ;;
        node)
            template="$TEMPLATES_DIR/env/nodejs.env.example"
            ;;
        react)
            template="$TEMPLATES_DIR/env/react.env.example"
            ;;
    esac
    
    # Create basic .env if template doesn't exist
    if [ ! -f "$template" ]; then
        create_basic_env_template "$template" "$BACKEND_TYPE"
    fi
    
    # Generate app key for Laravel
    local app_key=""
    if [ "$BACKEND_TYPE" == "laravel" ]; then
        app_key=$(php -r "echo 'base64:'.base64_encode(random_bytes(32));")
    fi
    
    # Determine DB port
    local db_port="3306"
    case "$DB_TYPE" in
        mysql) db_port="3306" ;;
        postgres) db_port="5432" ;;
        mongodb) db_port="27017" ;;
    esac
    
    # Read template and replace placeholders
    local sed_cmd="s|{{APP_NAME}}|$PROJECT_NAME|g"
    sed_cmd="$sed_cmd; s|{{APP_URL}}|http://$DOMAIN|g"
    sed_cmd="$sed_cmd; s|{{APP_KEY}}|$app_key|g"
    sed_cmd="$sed_cmd; s|{{DB_CONNECTION}}|$DB_TYPE|g"
    sed_cmd="$sed_cmd; s|{{DB_HOST}}|localhost|g"
    sed_cmd="$sed_cmd; s|{{DB_PORT}}|$db_port|g"
    sed_cmd="$sed_cmd; s|{{DB_DATABASE}}|$DB_NAME|g"
    sed_cmd="$sed_cmd; s|{{DB_USERNAME}}|$DB_USER|g"
    sed_cmd="$sed_cmd; s|{{DB_PASSWORD}}|$DB_PASSWORD|g"
    [ -n "${NODE_PORT:-}" ] && sed_cmd="$sed_cmd; s|{{NODE_PORT}}|$NODE_PORT|g"
    
    sed -e "$sed_cmd" "$template" > "$env_file"
    
    # Set permissions
    chown "$PROJECT_USER:$PROJECT_USER" "$env_file"
    chmod 600 "$env_file"
    
    log_success ".env file created"
}

create_basic_env_template() {
    local template=$1
    local backend_type=$2
    
    mkdir -p "$(dirname "$template")"
    
    case "$backend_type" in
        laravel)
            cat > "$template" <<'EOF'
APP_NAME={{APP_NAME}}
APP_ENV=production
APP_KEY={{APP_KEY}}
APP_DEBUG=false
APP_URL={{APP_URL}}

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION={{DB_CONNECTION}}
DB_HOST={{DB_HOST}}
DB_PORT={{DB_PORT}}
DB_DATABASE={{DB_DATABASE}}
DB_USERNAME={{DB_USERNAME}}
DB_PASSWORD={{DB_PASSWORD}}

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
EOF
            ;;
        node)
            cat > "$template" <<'EOF'
NODE_ENV=production
PORT={{NODE_PORT}}
APP_URL={{APP_URL}}

DB_HOST={{DB_HOST}}
DB_PORT={{DB_PORT}}
DB_NAME={{DB_DATABASE}}
DB_USER={{DB_USERNAME}}
DB_PASSWORD={{DB_PASSWORD}}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF
            ;;
        react)
            cat > "$template" <<'EOF'
REACT_APP_API_URL={{APP_URL}}
EOF
            ;;
    esac
}

###############################################################################
# Main Execution
###############################################################################

main() {
    check_root
    
    # Ask questions
    ask_questions
    
    # Create project
    create_project_structure
    create_linux_user
    allocate_port
    create_database
    generate_nginx_config
    create_env_file
    
    log_info ""
    log_success "=========================================="
    log_success "Project '$PROJECT_NAME' created successfully!"
    log_success "=========================================="
    log_info ""
    log_info "Project details:"
    log_info "  Domain: $DOMAIN"
    log_info "  User: $PROJECT_USER"
    log_info "  Database: $DB_NAME"
    [ -n "$NODE_PORT" ] && log_info "  Node.js Port: $NODE_PORT"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Point DNS for $DOMAIN to this server's IP"
    log_info "  2. Deploy code: ./bin/deploy.sh $PROJECT_NAME"
    if [ -n "$GIT_REPO" ]; then
        log_info "  3. Or deploy from Git: ./bin/deploy.sh $PROJECT_NAME $GIT_REPO"
    fi
    log_info "  4. Enable SSL: ./bin/enable-ssl.sh $PROJECT_NAME"
    log_info ""
    log_warning "Database credentials saved in: $PROJECTS_DIR/$PROJECT_NAME/shared/.env"
    log_info ""
}

# Run main function
main
