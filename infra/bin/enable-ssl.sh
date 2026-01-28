#!/bin/bash

###############################################################################
# HPanel - Enable SSL Script
# 
# Purpose: Automatically set up Let's Encrypt SSL certificate for a project
# Usage: sudo ./enable-ssl.sh PROJECT_NAME [EMAIL]
# 
# Example:
#   ./enable-ssl.sh myapp
#   ./enable-ssl.sh myapp admin@example.com
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
SERVICES_DIR="$INFRA_DIR/services"
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

check_certbot() {
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot is not installed"
        log_info "Run: ./bin/init-server.sh"
        exit 1
    fi
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
    
    # Find Nginx config
    local nginx_config=$(find "$SERVICES_DIR/nginx/sites-enabled" -name "*.conf" -exec grep -l "$project_name" {} \; | head -1)
    
    if [ -z "$nginx_config" ]; then
        log_error "Nginx configuration not found for project '$project_name'"
        exit 1
    fi
    
    NGINX_CONFIG="$nginx_config"
    
    # Extract domain from Nginx config
    DOMAIN=$(grep -E "^\s*server_name" "$NGINX_CONFIG" | head -1 | sed 's/.*server_name\s*\([^;]*\);.*/\1/' | xargs)
    
    if [ -z "$DOMAIN" ]; then
        log_error "Could not extract domain from Nginx config"
        exit 1
    fi
    
    log_success "Project validated: $project_name"
    log_info "Domain: $DOMAIN"
}

###############################################################################
# Check DNS
###############################################################################

check_dns() {
    local domain=$1
    
    log_info "Checking DNS configuration..."
    
    # Get server's public IP
    local server_ip=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
    
    if [ -z "$server_ip" ]; then
        log_warning "Could not determine server IP, skipping DNS check"
        return 0
    fi
    
    # Resolve domain
    local domain_ip=$(dig +short "$domain" | tail -1)
    
    if [ -z "$domain_ip" ]; then
        log_error "Domain '$domain' does not resolve to any IP"
        log_info "Please configure DNS to point to this server"
        exit 1
    fi
    
    if [ "$domain_ip" != "$server_ip" ]; then
        log_warning "Domain '$domain' resolves to $domain_ip, but server IP is $server_ip"
        log_warning "SSL verification may fail if DNS is not correct"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_success "DNS configured correctly ($domain → $server_ip)"
    fi
}

###############################################################################
# Get Email
###############################################################################

get_email() {
    local email=$1
    
    if [ -n "$email" ]; then
        echo "$email"
        return 0
    fi
    
    # Check config.env
    if [ -n "${SSL_EMAIL:-}" ]; then
        echo "$SSL_EMAIL"
        return 0
    fi
    
    # Ask user
    read -p "Email address for Let's Encrypt notifications: " email
    
    if [ -z "$email" ]; then
        log_error "Email is required"
        exit 1
    fi
    
    echo "$email"
}

###############################################################################
# Check if SSL Already Enabled
###############################################################################

check_ssl_enabled() {
    local nginx_config=$1
    
    if grep -q "ssl_certificate" "$nginx_config"; then
        log_warning "SSL appears to be already enabled for this project"
        read -p "Reconfigure SSL? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

###############################################################################
# Request Certificate
###############################################################################

request_certificate() {
    local domain=$1
    local email=$2
    
    log_info "Requesting SSL certificate from Let's Encrypt..."
    
    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        log_info "Certificate already exists, will renew if needed"
        certbot renew --cert-name "$domain" --quiet
    else
        # Request new certificate
        certbot certonly \
            --nginx \
            --non-interactive \
            --agree-tos \
            --email "$email" \
            --domains "$domain" \
            --preferred-challenges http \
            --keep-until-expiring
    fi
    
    if [ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        log_error "Certificate request failed"
        exit 1
    fi
    
    log_success "Certificate obtained"
}

###############################################################################
# Update Nginx Config
###############################################################################

update_nginx_config() {
    local nginx_config=$1
    local domain=$2
    local project_name=$3
    
    log_info "Updating Nginx configuration..."
    
    # Backup original config
    cp "$nginx_config" "${nginx_config}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Certificate paths
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    
    # Read current config
    local config_content=$(cat "$nginx_config")
    
    # Check if already has SSL
    if echo "$config_content" | grep -q "ssl_certificate"; then
        log_info "SSL configuration already present, updating..."
        # Update certificate paths if different
        sed -i "s|ssl_certificate.*|ssl_certificate $cert_path;|g" "$nginx_config"
        sed -i "s|ssl_certificate_key.*|ssl_certificate_key $key_path;|g" "$nginx_config"
    else
        # Add HTTP to HTTPS redirect
        local redirect_block="
# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}
"
        
        # Update main server block
        # Change listen 80 to listen 443 ssl http2
        sed -i "s/listen 80;/listen 443 ssl http2;/g" "$nginx_config"
        sed -i "s/listen \[::\]:80;/listen [::]:443 ssl http2;/g" "$nginx_config"
        
        # Add SSL configuration after server_name
        sed -i "/server_name/a\\
    # SSL Configuration\\
    ssl_certificate $cert_path;\\
    ssl_certificate_key $key_path;\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers HIGH:!aNULL:!MD5;\\
    ssl_prefer_server_ciphers on;\\
    ssl_session_cache shared:SSL:10m;\\
    ssl_session_timeout 10m;\\
\\
    # Security Headers\\
    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
" "$nginx_config"
        
        # Prepend redirect block
        echo "$redirect_block" > "${nginx_config}.new"
        cat "$nginx_config" >> "${nginx_config}.new"
        mv "${nginx_config}.new" "$nginx_config"
    fi
    
    log_success "Nginx configuration updated"
}

###############################################################################
# Test and Reload Nginx
###############################################################################

test_and_reload_nginx() {
    log_info "Testing Nginx configuration..."
    
    if nginx -t > /dev/null 2>&1; then
        log_success "Nginx configuration is valid"
        log_info "Reloading Nginx..."
        systemctl reload nginx
        log_success "Nginx reloaded"
    else
        log_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi
}

###############################################################################
# Setup Auto-Renewal
###############################################################################

setup_auto_renewal() {
    log_info "Setting up auto-renewal..."
    
    # Certbot already sets up renewal via systemd timer or cron
    # Just verify it's working
    if systemctl list-timers | grep -q "certbot.timer"; then
        log_success "Auto-renewal is configured (systemd timer)"
    elif [ -f "/etc/cron.d/certbot" ]; then
        log_success "Auto-renewal is configured (cron)"
    else
        log_warning "Auto-renewal may not be configured"
        log_info "Certificates expire in 90 days. Renew manually with: certbot renew"
    fi
}

###############################################################################
# Verify SSL
###############################################################################

verify_ssl() {
    local domain=$1
    
    log_info "Verifying SSL certificate..."
    
    sleep 2  # Give Nginx time to reload
    
    # Check if HTTPS is accessible
    local response=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" --max-time 10 || echo "000")
    
    if [ "$response" == "200" ] || [ "$response" == "301" ] || [ "$response" == "302" ]; then
        log_success "SSL is working! Visit: https://$domain"
    else
        log_warning "Could not verify SSL automatically (response code: $response)"
        log_info "Please check manually: https://$domain"
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    # Parse arguments
    PROJECT_NAME=${1:-}
    EMAIL=${2:-}
    
    if [ -z "$PROJECT_NAME" ]; then
        log_error "Usage: ./enable-ssl.sh PROJECT_NAME [EMAIL]"
        exit 1
    fi
    
    check_root
    check_certbot
    
    log_info "=========================================="
    log_info "HPanel - Enable SSL"
    log_info "=========================================="
    log_info ""
    
    # Validate project
    validate_project "$PROJECT_NAME"
    
    # Check DNS
    check_dns "$DOMAIN"
    
    # Get email
    EMAIL=$(get_email "$EMAIL")
    log_info "Email: $EMAIL"
    log_info ""
    
    # Check if already enabled
    check_ssl_enabled "$NGINX_CONFIG"
    
    # Request certificate
    request_certificate "$DOMAIN" "$EMAIL"
    
    # Update Nginx config
    update_nginx_config "$NGINX_CONFIG" "$DOMAIN" "$PROJECT_NAME"
    
    # Test and reload
    test_and_reload_nginx
    
    # Setup auto-renewal
    setup_auto_renewal
    
    # Verify SSL
    verify_ssl "$DOMAIN"
    
    log_info ""
    log_success "=========================================="
    log_success "SSL Enabled Successfully!"
    log_success "=========================================="
    log_info ""
    log_info "Project: $PROJECT_NAME"
    log_info "Domain: $DOMAIN"
    log_info "Certificate: /etc/letsencrypt/live/$DOMAIN/"
    log_info ""
    log_success "Your site is now accessible via HTTPS!"
    log_info "Visit: https://$DOMAIN"
    log_info ""
    log_info "Certificate will auto-renew before expiration (90 days)"
    log_info ""
}

# Run main function
main "$@"
