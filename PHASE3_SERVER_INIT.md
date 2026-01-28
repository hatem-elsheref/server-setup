# PHASE 3: Server Initialization Script

## 🎯 What This Script Does

The `init-server.sh` script sets up a **fresh Ubuntu 22.04 server** with all required services.

**Think of it like:** Running `npm install` for your entire infrastructure.

## 📦 What Gets Installed

### Core Services:
1. **Nginx** - Web server (routes requests to projects)
2. **PHP** - Multiple versions (7.4, 8.0, 8.1, 8.2, 8.3) with all extensions
3. **PHP-FPM** - PHP FastCGI Process Manager (runs PHP code)
4. **Composer** - PHP dependency manager

### Databases:
5. **MySQL** - Relational database
6. **PostgreSQL** - Advanced relational database
7. **MongoDB** - NoSQL database

### Caching & Queues:
8. **Redis** - In-memory cache & sessions
9. **RabbitMQ** - Message queue

### Storage:
10. **MinIO** - S3-compatible object storage

### Process Management:
11. **Supervisor** - Manages long-running processes (queues, workers)

### Mail:
12. **Postfix** - SMTP server (sends emails)
13. **Dovecot** - IMAP server (receives emails)

### File Transfer:
14. **vsftpd** - FTP server

### SSL:
15. **Certbot** - Let's Encrypt SSL certificates

### Utilities:
16. **Git** - Version control
17. **SSH** - Secure shell access
18. **Cron** - Scheduled tasks

## 🔧 How It Works (Simple Explanation)

### Step 1: Update System
```bash
apt update && apt upgrade -y
```
**Why?** Get latest security patches and package lists.

### Step 2: Install Each Service
For each service:
1. Install the package
2. Configure it
3. Start it
4. Enable auto-start on boot

### Step 3: Configure Services
- Create config files in `/infra/services/`
- Set secure passwords
- Configure ports
- Set up log rotation

### Step 4: Install PHP Extensions
For each PHP version:
- Install all common extensions (PDO, Redis, GD, Imagick, etc.)
- Configure PHP-FPM pools
- Set memory limits, timeouts

### Step 5: Setup System Users
- Create `www-data` user (if not exists)
- Set proper permissions
- Configure SSH access

## 🛡️ Safety Features

1. **Idempotent**: Safe to run multiple times
   - Checks if service already installed
   - Skips if already configured
   - Won't break existing setup

2. **Error Handling**:
   - Stops on errors
   - Shows clear error messages
   - Can resume from where it failed

3. **Backup Before Changes**:
   - Backs up existing configs
   - Can restore if something goes wrong

## 📝 What You'll Need

Before running the script:
1. **Ubuntu 22.04** server (fresh install recommended)
2. **Root or sudo access**
3. **Internet connection** (to download packages)
4. **Domain name** (optional, for SSL later)

## 🚀 Usage

```bash
# Make script executable
chmod +x /infra/bin/init-server.sh

# Run it
sudo /infra/bin/init-server.sh
```

The script will:
- Ask for confirmation
- Show progress for each service
- Take 10-30 minutes (depending on server speed)
- Show summary at the end

## ⚙️ Configuration

The script reads from `/infra/config.env` for:
- PHP versions to install
- Port ranges
- Default passwords (will prompt if not set)

## 📊 What Happens After

After successful installation:
- All services are running
- All services auto-start on boot
- Configs are in `/infra/services/`
- Ready to create your first project!

## 🔍 Verification

After installation, you can verify:
```bash
# Check services
systemctl status nginx
systemctl status mysql
systemctl status redis

# Check PHP versions
php7.4 -v
php8.0 -v
php8.1 -v
php8.2 -v
php8.3 -v

# Check installed extensions
php8.2 -m  # Lists all extensions
```

---

## 🤔 Key Concepts Explained

### 1. **PHP-FPM Pools**
- Each project can have its own PHP-FPM pool
- Pool = isolated PHP processes for that project
- Different PHP versions = different pools
- Like: Different workers for different projects

### 2. **Service Auto-Start**
- Services configured to start on boot
- If server reboots, services start automatically
- No manual intervention needed

### 3. **Port Management**
- Each service uses a specific port
- MySQL: 3306, Redis: 6379, etc.
- Ports are reserved in `ports.map`
- Firewall rules can be set based on ports

### 4. **Extension Installation**
- PHP extensions = additional features
- PDO = database access
- Redis = Redis client
- GD/Imagick = image processing
- All installed for all PHP versions

---

**Ready to see the actual script?**
