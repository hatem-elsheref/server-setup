#!/bin/bash

###############################################################################
# HPanel - Server Initialization Script
# 
# Purpose: Install and configure all required services on Ubuntu 22.04
# Usage: sudo ./init-server.sh
# 
# This script is SAFE TO RE-RUN (idempotent)
###############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$INFRA_DIR/config.env"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: config.env not found at $CONFIG_FILE${NC}"
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

check_installed() {
    if command -v "$1" &> /dev/null; then
        return 0  # Installed
    else
        return 1  # Not installed
    fi
}

install_if_missing() {
    local package=$1
    if check_installed "$package"; then
        log_info "$package is already installed, skipping..."
        return 0
    fi
    
    log_info "Installing $package..."
    apt-get install -y "$package" > /dev/null 2>&1
    log_success "$package installed"
}

service_is_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

ensure_service_running() {
    local service=$1
    if service_is_running "$service"; then
        log_info "$service is already running"
    else
        log_info "Starting $service..."
        systemctl start "$service"
        systemctl enable "$service"
        log_success "$service started and enabled"
    fi
}

###############################################################################
# System Preparation
###############################################################################

prepare_system() {
    log_info "Preparing system..."
    
    # Update package lists
    log_info "Updating package lists..."
    apt-get update -qq
    
    # Install basic utilities
    log_info "Installing basic utilities..."
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        fail2ban \
        > /dev/null 2>&1
    
    log_success "System prepared"
}

###############################################################################
# Nginx Installation
###############################################################################

install_nginx() {
    log_info "=== Installing Nginx ==="
    
    if check_installed nginx; then
        log_info "Nginx is already installed"
    else
        log_info "Installing Nginx..."
        apt-get install -y nginx > /dev/null 2>&1
        log_success "Nginx installed"
    fi
    
    # Create directories
    mkdir -p "$INFRA_DIR/services/nginx/sites-available"
    mkdir -p "$INFRA_DIR/services/nginx/sites-enabled"
    mkdir -p "$INFRA_DIR/logs/nginx"
    
    # Backup original config
    if [ ! -f /etc/nginx/nginx.conf.backup ]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    fi
    
    ensure_service_running nginx
    log_success "Nginx ready"
}

###############################################################################
# PHP Installation (Multiple Versions)
###############################################################################

install_php() {
    log_info "=== Installing PHP (Multiple Versions) ==="
    
    # Add PHP repository
    if [ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-jammy.list ]; then
        log_info "Adding PHP repository..."
        add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
        apt-get update -qq
    fi
    
    # PHP versions to install
    IFS=',' read -ra PHP_VERSIONS_ARRAY <<< "$PHP_VERSIONS"
    
    for version in "${PHP_VERSIONS_ARRAY[@]}"; do
        version=$(echo "$version" | xargs)  # Trim whitespace
        
        log_info "Installing PHP $version..."
        
        # Install PHP and common extensions
        apt-get install -y \
            "php${version}" \
            "php${version}-fpm" \
            "php${version}-cli" \
            "php${version}-common" \
            "php${version}-mysql" \
            "php${version}-pgsql" \
            "php${version}-sqlite3" \
            "php${version}-redis" \
            "php${version}-mongodb" \
            "php${version}-curl" \
            "php${version}-mbstring" \
            "php${version}-xml" \
            "php${version}-zip" \
            "php${version}-gd" \
            "php${version}-imagick" \
            "php${version}-intl" \
            "php${version}-bcmath" \
            "php${version}-soap" \
            "php${version}-opcache" \
            "php${version}-readline" \
            "php${version}-xdebug" \
            > /dev/null 2>&1
        
        # Create PHP-FPM pool directory
        mkdir -p "/etc/php/${version}/fpm/pool.d"
        mkdir -p "$INFRA_DIR/services/php/php${version}"
        mkdir -p "$INFRA_DIR/logs/php/php${version}"
        
        # Configure PHP-FPM
        ensure_service_running "php${version}-fpm"
        
        log_success "PHP $version installed with all extensions"
    done
    
    log_success "All PHP versions installed"
}

###############################################################################
# Composer Installation
###############################################################################

install_composer() {
    log_info "=== Installing Composer ==="
    
    if check_installed composer; then
        log_info "Composer is already installed"
    else
        log_info "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
        log_success "Composer installed"
    fi
}

###############################################################################
# MySQL Installation
###############################################################################

install_mysql() {
    log_info "=== Installing MySQL ==="
    
    if check_installed mysql; then
        log_info "MySQL is already installed"
    else
        log_info "Installing MySQL..."
        
        # Set MySQL root password if not set
        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
            log_warning "MySQL root password generated and saved to config.env"
            echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> "$CONFIG_FILE"
        fi
        
        # Install MySQL
        debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
        debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"
        
        apt-get install -y mysql-server mysql-client > /dev/null 2>&1
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/mysql"
        
        # Secure MySQL
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        
        log_success "MySQL installed and secured"
    fi
    
    ensure_service_running mysql
    log_success "MySQL ready"
}

###############################################################################
# PostgreSQL Installation
###############################################################################

install_postgresql() {
    log_info "=== Installing PostgreSQL ==="
    
    if check_installed psql; then
        log_info "PostgreSQL is already installed"
    else
        log_info "Installing PostgreSQL..."
        apt-get install -y postgresql postgresql-contrib > /dev/null 2>&1
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/postgresql"
        
        log_success "PostgreSQL installed"
    fi
    
    ensure_service_running postgresql
    log_success "PostgreSQL ready"
}

###############################################################################
# MongoDB Installation
###############################################################################

install_mongodb() {
    log_info "=== Installing MongoDB ==="
    
    if check_installed mongod; then
        log_info "MongoDB is already installed"
    else
        log_info "Installing MongoDB..."
        
        # Add MongoDB repository
        if [ ! -f /etc/apt/sources.list.d/mongodb-org-6.0.list ]; then
            curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
            apt-get update -qq
        fi
        
        apt-get install -y mongodb-org > /dev/null 2>&1
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/mongodb"
        
        log_success "MongoDB installed"
    fi
    
    ensure_service_running mongod
    log_success "MongoDB ready"
}

###############################################################################
# Redis Installation
###############################################################################

install_redis() {
    log_info "=== Installing Redis ==="
    
    if check_installed redis-server; then
        log_info "Redis is already installed"
    else
        log_info "Installing Redis..."
        apt-get install -y redis-server > /dev/null 2>&1
        
        # Set password if configured
        if [ -n "$REDIS_PASSWORD" ]; then
            sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
        fi
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/redis"
        cp /etc/redis/redis.conf "$INFRA_DIR/services/redis/redis.conf"
        
        log_success "Redis installed"
    fi
    
    ensure_service_running redis-server
    log_success "Redis ready"
}

###############################################################################
# RabbitMQ Installation
###############################################################################

#install_rabbitmq() {
#    log_info "=== Installing RabbitMQ ==="
#
#    if check_installed rabbitmq-server; then
#        log_info "RabbitMQ is already installed"
#    else
#        log_info "Installing RabbitMQ..."
#
#        # Add Erlang repository (RabbitMQ dependency)
#        if [ ! -f /etc/apt/sources.list.d/rabbitmq.list ]; then
#            curl -fsSL https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key | gpg --dearmor > /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg
#            echo "deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/ubuntu jammy main" | tee /etc/apt/sources.list.d/rabbitmq-erlang.list
#            echo "deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq/ubuntu jammy main" | tee /etc/apt/sources.list.d/rabbitmq.list
#            apt-get update -qq
#        fi
#
#        apt-get install -y rabbitmq-server > /dev/null 2>&1
#
#        # Enable management plugin
#        rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1
#
#        # Create config directory
#        mkdir -p "$INFRA_DIR/services/rabbitmq"
#
#        log_success "RabbitMQ installed"
#    fi
#
#    ensure_service_running rabbitmq-server
#    log_success "RabbitMQ ready"
#}

###############################################################################
# MinIO Installation
###############################################################################

install_minio() {
    log_info "=== Installing MinIO ==="
    
    if [ -f /usr/local/bin/minio ]; then
        log_info "MinIO is already installed"
    else
        log_info "Installing MinIO..."
        
        # Download MinIO
        wget -q https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
        chmod +x /usr/local/bin/minio
        
        # Create MinIO user
        if ! id "minio" &>/dev/null; then
            useradd -r -s /bin/false minio
        fi
        
        # Create data directory
        mkdir -p /var/lib/minio/data
        chown minio:minio /var/lib/minio/data
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/minio"
        
        # Create systemd service
        cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=minio
ExecStart=/usr/local/bin/minio server /var/lib/minio/data --console-address ":9001"
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        log_success "MinIO installed"
    fi
    
    ensure_service_running minio
    log_success "MinIO ready"
}

###############################################################################
# Supervisor Installation
###############################################################################

install_supervisor() {
    log_info "=== Installing Supervisor ==="
    
    if check_installed supervisor; then
        log_info "Supervisor is already installed"
    else
        log_info "Installing Supervisor..."
        apt-get install -y supervisor > /dev/null 2>&1
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/supervisor"
        
        log_success "Supervisor installed"
    fi
    
    ensure_service_running supervisor
    log_success "Supervisor ready"
}

###############################################################################
# Postfix & Dovecot Installation
###############################################################################

install_mail() {
    log_info "=== Installing Mail Services (Postfix + Dovecot) ==="
    
    # Install Postfix
    if check_installed postfix; then
        log_info "Postfix is already installed"
    else
        log_info "Installing Postfix..."
        debconf-set-selections <<< "postfix postfix/mailname string ${POSTFIX_DOMAIN:-localhost}"
        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
        apt-get install -y postfix > /dev/null 2>&1
        
        mkdir -p "$INFRA_DIR/services/postfix"
        log_success "Postfix installed"
    fi
    
    # Install Dovecot
    if check_installed dovecot-core; then
        log_info "Dovecot is already installed"
    else
        log_info "Installing Dovecot..."
        apt-get install -y dovecot-core dovecot-imapd dovecot-pop3d > /dev/null 2>&1
        
        mkdir -p "$INFRA_DIR/services/dovecot"
        log_success "Dovecot installed"
    fi
    
    ensure_service_running postfix
    ensure_service_running dovecot
    log_success "Mail services ready"
}

###############################################################################
# vsftpd Installation
###############################################################################

install_vsftpd() {
    log_info "=== Installing vsftpd (FTP Server) ==="
    
    if check_installed vsftpd; then
        log_info "vsftpd is already installed"
    else
        log_info "Installing vsftpd..."
        apt-get install -y vsftpd > /dev/null 2>&1
        
        # Create config directory
        mkdir -p "$INFRA_DIR/services/vsftpd"
        
        log_success "vsftpd installed"
    fi
    
    ensure_service_running vsftpd
    log_success "vsftpd ready"
}

###############################################################################
# Certbot Installation
###############################################################################

install_certbot() {
    log_info "=== Installing Certbot (SSL) ==="
    
    if check_installed certbot; then
        log_info "Certbot is already installed"
    else
        log_info "Installing Certbot..."
        apt-get install -y certbot python3-certbot-nginx > /dev/null 2>&1
        log_success "Certbot installed"
    fi
}

###############################################################################
# Node.js Installation (for Node.js projects)
###############################################################################

install_nodejs() {
    log_info "=== Installing Node.js ==="
    
    if check_installed node; then
        log_info "Node.js is already installed"
    else
        log_info "Installing Node.js..."
        
        # Install Node.js 20.x (LTS)
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs > /dev/null 2>&1
        
        log_success "Node.js installed"
    fi
    
    # Install PM2 globally (process manager for Node.js)
    if ! command -v pm2 &> /dev/null; then
        log_info "Installing PM2..."
        npm install -g pm2 > /dev/null 2>&1
        log_success "PM2 installed"
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    log_info "=========================================="
    log_info "HPanel - Server Initialization"
    log_info "=========================================="
    log_info ""
    
    # Check if running as root
    check_root
    
    # Confirm before proceeding
    log_warning "This script will install and configure all required services."
    log_warning "This may take 10-30 minutes depending on your server speed."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi
    
    log_info ""
    log_info "Starting installation..."
    log_info ""
    
    # Run installations
    prepare_system
    install_nginx
    install_php
    install_composer
    install_mysql
    install_postgresql
    install_mongodb
    install_redis
    #install_rabbitmq
    install_minio
    install_supervisor
    install_mail
    install_vsftpd
    install_certbot
    install_nodejs
    
    log_info ""
    log_success "=========================================="
    log_success "Installation Complete!"
    log_success "=========================================="
    log_info ""
    log_info "All services are installed and running."
    log_info "You can now create your first project!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run: ./bin/create-project.sh"
    log_info "  2. Follow the interactive prompts"
    log_info ""
}

# Run main function
main
#6tQMdhY+h+g2kiAEILtdnBkZc2nk0QGCGeLzIGAyOjo=

#g2kiAEILtdnBkZc2nk0QGCGeLzIGAyOjo

#
# New MySQL root password: nesfFE7PPvPt+MQ2l5Q/2DQhuNyHs0w5GEc2MXVBvmc=
ftp ftp_ceramic_root_100200300

sudo chown -R ftpuser:ftpuser /var/www/projects/myproject
/var/www/projects/ceramic

hatem-ceramic