# PHASE 4: Project Creation Script

## 🎯 What This Script Does

The `create-project.sh` script is an **interactive tool** that sets up a new project from scratch.

**Think of it like:** Running `npm init` but for infrastructure - it asks questions and sets everything up.

## 📋 What It Does (Step by Step)

### 1. **Asks Questions (Interactive)**
   - Project name? (e.g., "myapp")
   - Domain/subdomain? (e.g., "myapp.example.com")
   - Backend type? (Laravel / Node.js / React SPA)
   - Database type? (MySQL / PostgreSQL / MongoDB / None)
   - PHP version? (if Laravel: 7.4, 8.0, 8.1, 8.2, 8.3)
   - Git repository URL? (optional, can deploy later)

### 2. **Creates Project Structure**
   ```
   /infra/projects/myapp/
     ├── current/          → Symlink (will point to latest release)
     ├── releases/         → Empty (releases added during deployment)
     └── shared/           → Persistent files
         ├── .env          → Environment file
         └── storage/      → Laravel storage (if Laravel)
   ```

### 3. **Creates Linux User**
   - Username: `myapp_user` (based on project name)
   - UID: Auto-assigned (starting from 10000)
   - Home directory: `/infra/projects/myapp/`
   - Group: Same as username

### 4. **Sets Permissions**
   - Project folder owned by: `myapp_user:myapp_user`
   - Permissions: 755 (owner can read/write, others can read)
   - `.env` file: 600 (only owner can read/write)

### 5. **Creates Database**
   - Database name: `myapp_db`
   - Database user: `myapp_user`
   - Database password: Auto-generated (secure random)
   - Grants permissions: User can only access their database

### 6. **Generates Nginx Config**
   - Reads template from `/infra/templates/nginx/`
   - Replaces placeholders: `{{PROJECT_NAME}}`, `{{DOMAIN}}`, etc.
   - Saves to `/infra/services/nginx/sites-available/myapp.conf`
   - Creates symlink to `sites-enabled/`
   - Tests config and reloads Nginx

### 7. **Updates Tracking Files**
   - `ports.map`: Records which port (if Node.js)
   - `users.map`: Records user ownership

### 8. **Creates .env File**
   - Generates from template
   - Fills in database credentials
   - Sets app URL, app key (if Laravel), etc.

## 🔒 Security Features

1. **User Isolation**
   - Each project has its own user
   - User can only access their own files
   - User can only access their own database

2. **Secure Passwords**
   - Database passwords: 32-character random
   - App keys: 32-character random (Laravel)
   - Stored in `.env` (not in Git)

3. **File Permissions**
   - `.env`: 600 (only owner)
   - Code: 755 (readable, writable by owner)
   - Storage: 775 (writable by web server)

## 📝 Example Interaction

```bash
$ ./bin/create-project.sh

=== HPanel - Create New Project ===

Project name: myapp
Domain/subdomain: myapp.example.com
Backend type [laravel/node/react]: laravel
Database type [mysql/postgres/mongodb/none]: mysql
PHP version [7.4/8.0/8.1/8.2/8.3]: 8.2
Git repository URL (optional): https://github.com/user/myapp.git

Creating project structure...
Creating Linux user...
Setting permissions...
Creating database...
Generating Nginx config...
Updating tracking files...

✅ Project 'myapp' created successfully!

Next steps:
  1. Deploy: ./bin/deploy.sh myapp
  2. Enable SSL: ./bin/enable-ssl.sh myapp
```

## 🎯 Key Concepts

### 1. **Project Name**
   - Used for: folder name, user name, database name
   - Must be: lowercase, alphanumeric, no spaces
   - Example: "myapp" → user: "myapp_user", db: "myapp_db"

### 2. **Domain/Subdomain**
   - Full domain: "myapp.example.com"
   - Nginx will route this to the project
   - Must point to your server's IP (DNS)

### 3. **Backend Type**
   - **Laravel**: PHP framework, needs PHP-FPM
   - **Node.js**: Express, Socket.IO, needs Node process
   - **React SPA**: Static files, just serves HTML/JS/CSS

### 4. **Database Type**
   - **MySQL**: Most common, good for Laravel
   - **PostgreSQL**: Advanced features, better for complex data
   - **MongoDB**: NoSQL, good for flexible schemas
   - **None**: No database needed (static site)

### 5. **PHP Version**
   - Each project can use different PHP version
   - Laravel 9+ needs PHP 8.1+
   - Older Laravel might need PHP 7.4 or 8.0
   - PHP-FPM pool created for that version

## 🔄 What Happens After Creation

After running the script:
1. ✅ Project folder exists
2. ✅ Linux user created
3. ✅ Database created (if selected)
4. ✅ Nginx config ready (but site not active until DNS points)
5. ✅ `.env` file created with credentials
6. ⏳ Code not deployed yet (run `deploy.sh` next)

## 🛡️ Safety Features

1. **Validation**
   - Checks if project name already exists
   - Checks if domain already in use
   - Validates domain format
   - Checks if user already exists

2. **Idempotent**
   - Safe to re-run (won't duplicate)
   - Can update configs if needed

3. **Rollback**
   - Can delete project (separate script)
   - Removes user, database, Nginx config

---

**Ready to see the actual script?**
