# PHASE 2: Detailed Folder Structure

## 📁 Complete Structure Overview

```
/infra
  /bin                    → Executable scripts (your CLI tools)
    init-server.sh        → Install all services (run once)
    create-project.sh     → Create new project (interactive)
    deploy.sh             → Deploy project from Git
    enable-ssl.sh         → Setup SSL certificate
    setup-supervisor.sh   → Configure Supervisor for queues
    setup-cron.sh         → Setup Laravel scheduler
    rollback.sh           → Rollback to previous deployment
    list-projects.sh      → List all projects
    project-info.sh       → Show project details
    
  /templates              → Reusable configuration templates
    nginx/
      laravel.conf        → Nginx config for Laravel
      nodejs.conf         → Nginx config for Node.js
      react.conf          → Nginx config for React SPA
    supervisor/
      laravel-queue.conf  → Supervisor config for Laravel queues
      nodejs.conf         → Supervisor config for Node.js
    php/
      php-fpm-pool.conf   → PHP-FPM pool template
    env/
      laravel.env.example → Laravel .env template
      nodejs.env.example  → Node.js .env template
    
  /services               → Shared services configuration
    nginx/
      nginx.conf          → Main Nginx config
      sites-available/    → All site configs (symlinked to sites-enabled)
      sites-enabled/      → Active sites
    mysql/
      my.cnf              → MySQL configuration
    php/
      php7.4/             → PHP 7.4 configs
      php8.0/             → PHP 8.0 configs
      php8.1/             → PHP 8.1 configs
      php8.2/             → PHP 8.2 configs
      php8.3/             → PHP 8.3 configs
    redis/
      redis.conf          → Redis configuration
    postgresql/
      postgresql.conf     → PostgreSQL configuration
    mongodb/
      mongod.conf         → MongoDB configuration
    rabbitmq/
      rabbitmq.conf       → RabbitMQ configuration
    minio/
      config.json         → MinIO configuration
    postfix/
      main.cf             → Postfix configuration
    dovecot/
      dovecot.conf        → Dovecot configuration
    vsftpd/
      vsftpd.conf         → vsftpd configuration
    
  /projects               → All your applications
    project1/             → Example project
      current/            → Symlink to current deployment
      releases/           → All deployment versions
        v1.0.0/
        v1.0.1/
      shared/             → Shared files (uploads, logs, etc.)
        storage/          → Laravel storage
        .env              → Environment file
      .git/               → Git repository
    
  /logs                   → Centralized logging
    nginx/                → Nginx access/error logs
    php/                  → PHP-FPM logs
    projects/             → Project-specific logs
      project1/
      project2/
    
  ports.map               → Port allocation tracking
  users.map               → User ownership tracking
  config.env              → System-wide configuration
```

---

## 📂 Detailed Explanation of Each Component

### `/infra/bin/` - Your CLI Tools

**Purpose:** Executable scripts that you run to manage your PaaS.

**Think of it like:** npm scripts, but for infrastructure.

**Key Scripts:**

1. **`init-server.sh`**
   - Run ONCE when setting up a new server
   - Installs all services (Nginx, PHP, MySQL, etc.)
   - Configures everything
   - Safe to re-run (checks if already installed)

2. **`create-project.sh`**
   - Interactive script (asks questions)
   - Creates project folder, user, database
   - Generates Nginx config
   - Sets permissions

3. **`deploy.sh`**
   - Deploys project from Git
   - Zero-downtime deployment
   - Creates new release folder
   - Updates symlink atomically

4. **`enable-ssl.sh`**
   - Runs Certbot
   - Gets Let's Encrypt certificate
   - Updates Nginx config
   - Auto-renewal setup

**Why separate scripts?**
- Modular: Each script does ONE thing
- Reusable: Can run scripts independently
- Testable: Easy to test each function
- Readable: Clear purpose for each script

---

### `/infra/templates/` - Configuration Templates

**Purpose:** Reusable config files. Like `.env.example` but for infrastructure.

**How it works:**
1. Template has placeholders: `{{PROJECT_NAME}}`, `{{DOMAIN}}`, etc.
2. Script copies template
3. Script replaces placeholders with real values
4. Saves to final location

**Example:**
```nginx
# Template: nginx/laravel.conf
server {
    server_name {{DOMAIN}};
    root {{PROJECT_ROOT}}/current/public;
    # ...
}

# After processing:
server {
    server_name myproject.example.com;
    root /infra/projects/myproject/current/public;
    # ...
}
```

**Why templates?**
- Don't write configs from scratch every time
- Consistent structure
- Easy to update (change template, regenerate all)

---

### `/infra/services/` - Shared Services Config

**Purpose:** Configuration for services that run ONCE (shared across all projects).

**Key Services:**

1. **`nginx/`**
   - Main Nginx config
   - `sites-available/` = all configs (inactive)
   - `sites-enabled/` = active configs (symlinks)
   - Like: All apps installed, but only some enabled

2. **`php/`**
   - Separate folder for each PHP version
   - Each version has its own PHP-FPM config
   - Projects choose which version to use

3. **`mysql/`, `redis/`, etc.**
   - One config file per service
   - Shared by all projects
   - Projects connect to same service, different databases

**Why here?**
- Centralized: All service configs in one place
- Easy to backup: One folder to backup
- Clear separation: Service configs vs project configs

---

### `/infra/projects/` - Your Applications

**Purpose:** Where all your projects live.

**Structure per project:**
```
project1/
  current/          → Symlink to latest release (for zero-downtime)
  releases/         → All versions (v1.0.0, v1.0.1, etc.)
  shared/           → Files that persist across deployments
    .env            → Environment file (not in Git)
    storage/        → Laravel storage (uploads, cache)
    logs/           → Application logs
  .git/             → Git repository
```

**Why this structure?**
- **`current/`**: Nginx always points here. When deploying, we update the symlink atomically (zero downtime)
- **`releases/`**: Keep old versions for rollback
- **`shared/`**: Files that shouldn't be overwritten (uploads, .env)

**Deployment flow:**
1. Clone Git → `releases/v1.0.1/`
2. Install dependencies
3. Link `shared/.env` → `releases/v1.0.1/.env`
4. Update `current/` symlink → `releases/v1.0.1/`
5. Done! (Nginx already points to `current/`)

---

### `/infra/logs/` - Centralized Logging

**Purpose:** All logs in one place for easy debugging.

**Structure:**
```
logs/
  nginx/            → Nginx access.log, error.log
  php/              → PHP-FPM logs (all versions)
  projects/         → Project-specific logs
    project1/
      app.log
      queue.log
```

**Why centralized?**
- Easy to find logs
- Can set up log rotation
- Better for monitoring

---

### `ports.map` - Port Tracking

**Purpose:** Simple text file to track which ports are used.

**Format:**
```
project1:8001:node
project2:8002:node
project3:9001:php-fpm
```

**How it works:**
- Script reads file before assigning port
- Checks if port is available
- Writes new entry when assigning
- Prevents conflicts

**Why not just pick random ports?**
- Predictable: Know which port each project uses
- Debugging: Easy to check which project uses which port
- Firewall: Can open specific ports

---

### `users.map` - User Tracking

**Purpose:** Track which Linux user owns which project.

**Format:**
```
project1:project1_user:10001
project2:project2_user:10002
```

**How it works:**
- Script reads file before creating user
- Assigns next available UID (starting from 10000)
- Writes entry when creating user
- Used for permission management

**Why track this?**
- Easy to see project ownership
- Can recreate users if needed
- Debugging permissions issues

---

### `config.env` - System Configuration

**Purpose:** System-wide settings (not project-specific).

**Example:**
```bash
DOMAIN=example.com
NGINX_USER=www-data
PHP_VERSIONS=7.4,8.0,8.1,8.2,8.3
MYSQL_ROOT_PASSWORD=...
REDIS_PASSWORD=...
```

**Why separate from project configs?**
- Server-level settings
- Shared by all projects
- Easy to update system-wide

---

## 🎯 Key Design Decisions

### 1. **Symlinks for Zero-Downtime**
- `current/` is a symlink
- Update symlink = instant (atomic operation)
- No service restart needed

### 2. **Releases Folder**
- Keep old versions
- Easy rollback
- Can compare versions

### 3. **Shared Folder**
- Separate from code
- Persists across deployments
- Contains user-generated content

### 4. **Templates**
- DRY principle (Don't Repeat Yourself)
- Consistent configs
- Easy maintenance

### 5. **Centralized Services**
- One config per service
- Shared resources
- Efficient resource usage

---

## ✅ What Makes This Structure Good

1. **Modular**: Each folder has clear purpose
2. **Scalable**: Easy to add more projects
3. **Maintainable**: Easy to find and fix issues
4. **Safe**: Can't accidentally break other projects
5. **Readable**: Clear naming, obvious structure

---

## 🤔 Questions to Check Understanding

1. **Why `current/` symlink?** → Zero-downtime deployments
2. **Why `releases/` folder?** → Keep old versions for rollback
3. **Why `shared/` folder?** → Files that persist (uploads, .env)
4. **Why templates?** → Don't write configs from scratch
5. **Why centralized services?** → One service, many databases

---

**Ready for Phase 3?** (Creating the actual scripts)
