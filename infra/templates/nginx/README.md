# Nginx Templates

This directory contains Nginx configuration templates for different project types.

## Available Templates

### `laravel.conf`
For Laravel PHP applications.

**Features:**
- PHP-FPM integration
- Laravel routing (all requests → index.php)
- Static file caching
- Security headers
- Hidden file protection

**Placeholders:**
- `{{DOMAIN}}` - Full domain (e.g., myapp.example.com)
- `{{PROJECT_ROOT}}` - Project directory path
- `{{PHP_VERSION}}` - PHP version (e.g., 8.2)
- `{{PROJECT_NAME}}` - Project name

### `nodejs.conf`
For Node.js applications (Express, Socket.IO, etc.).

**Features:**
- Reverse proxy to Node.js process
- WebSocket support (Socket.IO)
- Proper header forwarding
- Timeout configuration

**Placeholders:**
- `{{DOMAIN}}` - Full domain
- `{{PROJECT_ROOT}}` - Project directory path
- `{{NODE_PORT}}` - Node.js port number
- `{{PROJECT_NAME}}` - Project name

### `react.conf`
For React Single Page Applications (static builds).

**Features:**
- Client-side routing support
- Static file serving
- Gzip compression
- Asset caching

**Placeholders:**
- `{{DOMAIN}}` - Full domain
- `{{PROJECT_ROOT}}` - Project directory path
- `{{PROJECT_NAME}}` - Project name

## Usage

Templates are automatically used by `create-project.sh` when creating new projects.

The script:
1. Reads the appropriate template
2. Replaces placeholders with actual values
3. Saves to `/infra/services/nginx/sites-available/`
4. Creates symlink in `sites-enabled/`
5. Reloads Nginx

## Customization

You can customize these templates for your needs:
- Add custom headers
- Modify caching rules
- Add API proxy rules
- Adjust timeouts

After modifying templates, existing projects won't be affected. Only new projects will use the updated templates.

## SSL

Templates are prepared for SSL. When you run `enable-ssl.sh`, it will:
- Add SSL configuration
- Redirect HTTP to HTTPS
- Include Let's Encrypt certificates
