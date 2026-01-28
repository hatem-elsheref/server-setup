# HPanel Scripts

This directory contains all executable scripts for managing your PaaS.

## Available Scripts

### `init-server.sh`
**Purpose:** Install all required services on a fresh Ubuntu 22.04 server.

**Usage:**
```bash
sudo ./bin/init-server.sh
```

**What it installs:**
- Nginx (web server)
- PHP 7.4, 8.0, 8.1, 8.2, 8.3 (with all extensions)
- Composer
- MySQL, PostgreSQL, MongoDB
- Redis, RabbitMQ
- MinIO
- Supervisor
- Postfix, Dovecot
- vsftpd
- Certbot
- Node.js, PM2

**Safety:**
- Safe to re-run (idempotent)
- Checks if services already installed
- Won't break existing setup

**Time:** 10-30 minutes depending on server speed

---

## Scripts Coming in Next Phases

- `create-project.sh` - Create new project (interactive)
- `deploy.sh` - Deploy project from Git
- `enable-ssl.sh` - Setup SSL certificate
- `setup-supervisor.sh` - Configure Supervisor
- `setup-cron.sh` - Setup Laravel scheduler
- `rollback.sh` - Rollback deployment
- `list-projects.sh` - List all projects
- `project-info.sh` - Show project details

---

## Making Scripts Executable

All scripts should be executable. If you get "permission denied":

```bash
chmod +x ./bin/script-name.sh
```
