# PHASE 5: Nginx Automation

## 🎯 What This Phase Does

This phase creates **proper Nginx templates** and explains how Nginx routes requests to your projects.

**Think of Nginx as:** A smart doorman that looks at the address (domain) and directs visitors to the right apartment (project).

## 🔄 How Nginx Routing Works (Simple)

### The Flow:

```
1. User visits: myapp.example.com
   ↓
2. Request arrives at Nginx (port 80/443)
   ↓
3. Nginx checks: "Which project uses myapp.example.com?"
   ↓
4. Nginx finds config: /infra/services/nginx/sites-enabled/myapp.example.com.conf
   ↓
5. Nginx reads: "root = /infra/projects/myapp/current/public"
   ↓
6. Nginx serves files OR proxies to PHP-FPM/Node.js
   ↓
7. Response sent back to user
```

### Key Concept: Server Blocks

Each project gets a **server block** (configuration section) in Nginx:

```nginx
server {
    listen 80;
    server_name myapp.example.com;  # This domain
    root /infra/projects/myapp/current/public;  # Where files are
    
    # Rules for serving files...
}
```

When someone visits `myapp.example.com`, Nginx:
1. Matches the `server_name`
2. Uses that server block's rules
3. Serves from the `root` directory

## 📁 Nginx Directory Structure

```
/etc/nginx/                    → System Nginx (we don't touch this)
/infra/services/nginx/         → Our Nginx configs
  ├── sites-available/         → All configs (inactive)
  │   ├── myapp.conf
  │   └── otherapp.conf
  └── sites-enabled/            → Active configs (symlinks)
      ├── myapp.conf → ../sites-available/myapp.conf
      └── otherapp.conf → ../sites-available/otherapp.conf
```

**Why two directories?**
- **sites-available**: All configs stored here (like a library)
- **sites-enabled**: Only active configs (symlinks)
- Easy to enable/disable: Create/remove symlink

## 🎨 Template System

### How Templates Work:

1. **Template has placeholders:**
   ```nginx
   server_name {{DOMAIN}};
   root {{PROJECT_ROOT}}/current/public;
   ```

2. **Script replaces placeholders:**
   ```bash
   {{DOMAIN}} → myapp.example.com
   {{PROJECT_ROOT}} → /infra/projects/myapp
   ```

3. **Result:**
   ```nginx
   server_name myapp.example.com;
   root /infra/projects/myapp/current/public;
   ```

### Why Templates?
- **DRY**: Don't write same config 100 times
- **Consistent**: All projects use same structure
- **Easy updates**: Change template, regenerate all

## 🔧 Different Configs for Different Backends

### 1. Laravel (PHP)

**How it works:**
- Nginx serves static files (CSS, JS, images)
- PHP files → sent to PHP-FPM (PHP processor)
- PHP-FPM runs PHP code, returns HTML
- Nginx sends HTML to user

**Key features:**
- `try_files`: Laravel routing (all requests → index.php)
- `fastcgi_pass`: Sends PHP to PHP-FPM socket
- `fastcgi_params`: Passes request info to PHP

### 2. Node.js

**How it works:**
- Nginx doesn't serve files directly
- Nginx **proxies** all requests to Node.js process
- Node.js runs on a port (e.g., 8001)
- Nginx forwards requests to that port

**Key features:**
- `proxy_pass`: Forwards to Node.js
- `proxy_set_header`: Passes original request info
- WebSocket support (for Socket.IO)

### 3. React SPA (Static)

**How it works:**
- Nginx serves static files (HTML, JS, CSS)
- All routes → index.html (client-side routing)
- No backend needed

**Key features:**
- `try_files`: All routes → index.html
- Simple file serving

## 🔒 Security Features in Templates

1. **Hide .env files:**
   ```nginx
   location ~ /\.(?!well-known).* {
       deny all;
   }
   ```
   Prevents access to `.env`, `.git`, etc.

2. **Limit file upload size:**
   ```nginx
   client_max_body_size 10M;
   ```
   Prevents huge uploads

3. **Hide server info:**
   ```nginx
   server_tokens off;
   ```
   Doesn't reveal Nginx version

## 🚀 SSL Preparation

Templates are ready for SSL:
- HTTP (port 80) → redirects to HTTPS (when SSL enabled)
- HTTPS (port 443) → serves content securely

We'll add SSL in Phase 7, but templates are ready.

## 📝 Template Placeholders

| Placeholder | Replaced With | Example |
|------------|---------------|---------|
| `{{DOMAIN}}` | Full domain | `myapp.example.com` |
| `{{PROJECT_NAME}}` | Project name | `myapp` |
| `{{PROJECT_ROOT}}` | Project directory | `/infra/projects/myapp` |
| `{{PHP_VERSION}}` | PHP version | `8.2` |
| `{{NODE_PORT}}` | Node.js port | `8001` |

## 🔄 How create-project.sh Uses Templates

1. User creates project: `myapp`
2. Script reads template: `templates/nginx/laravel.conf`
3. Script replaces placeholders
4. Saves to: `services/nginx/sites-available/myapp.example.com.conf`
5. Creates symlink: `sites-enabled/myapp.example.com.conf`
6. Tests config: `nginx -t`
7. Reloads Nginx: `systemctl reload nginx`

## ✅ What Makes Good Nginx Configs

1. **Performance:**
   - Gzip compression (smaller files)
   - Caching headers (faster repeat visits)
   - Keep-alive connections

2. **Security:**
   - Hide sensitive files
   - Limit upload size
   - Proper headers

3. **Laravel-specific:**
   - All routes → index.php
   - Proper PHP-FPM configuration
   - Static file serving

4. **Node.js-specific:**
   - WebSocket support
   - Proper proxy headers
   - Timeout settings

---

**Ready to see the actual templates?**
