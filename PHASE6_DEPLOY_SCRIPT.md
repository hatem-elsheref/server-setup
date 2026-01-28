# PHASE 6: Deploy Script (Zero-Downtime Deployment)

## 🎯 What This Script Does

The `deploy.sh` script deploys your code from Git to the server **without any downtime**.

**Think of it like:** Updating your app while users are still using it - they won't notice!

## 🔄 Zero-Downtime Deployment (Simple Explanation)

### The Problem (Bad Way):
```
1. Stop app
2. Update code
3. Start app
```
**Result:** Users see "Site down" during update ❌

### The Solution (Good Way):
```
1. Clone code to NEW folder (releases/v1.0.1/)
2. Install dependencies
3. Test everything works
4. Update symlink: current → releases/v1.0.1/
```
**Result:** Switch is instant, no downtime ✅

### How Symlinks Work:

```
Before deployment:
current → releases/v1.0.0/

During deployment:
current → releases/v1.0.0/  (still serving old version)
releases/v1.0.1/            (new version being prepared)

After deployment:
current → releases/v1.0.1/  (switched instantly!)
```

The symlink update is **atomic** (happens instantly), so there's no gap where the site is broken.

## 📋 Deployment Steps (What the Script Does)

### 1. **Validate Project**
   - Check if project exists
   - Check if Git repo is accessible
   - Verify project structure

### 2. **Create New Release Folder**
   ```
   /infra/projects/myapp/releases/v1.0.1/
   ```
   - Version based on timestamp or Git tag
   - Fresh folder for new code

### 3. **Clone/Pull Code**
   - If first deployment: `git clone`
   - If update: `git pull` (or clone to new folder)
   - Checkout specific branch/tag if specified

### 4. **Install Dependencies**
   - **Laravel**: `composer install --no-dev --optimize-autoloader`
   - **Node.js**: `npm install --production`
   - **React**: `npm install && npm run build`

### 5. **Link Shared Files**
   - Symlink `.env` from `shared/` to release folder
   - Symlink `storage/` (Laravel) from `shared/` to release folder
   - These files persist across deployments

### 6. **Build Assets (if needed)**
   - **Laravel**: `php artisan config:cache`, `php artisan route:cache`
   - **React**: Already built in step 4
   - **Node.js**: No build needed

### 7. **Run Migrations (Laravel)**
   - `php artisan migrate --force`
   - Only runs new migrations
   - Safe to run multiple times

### 8. **Test New Version**
   - Check if files exist
   - Verify symlinks work
   - Test basic functionality (optional)

### 9. **Switch to New Version (Atomic)**
   - Update `current/` symlink → new release folder
   - This is instant! No downtime!

### 10. **Restart Services**
   - **Laravel**: Reload PHP-FPM (picks up new code)
   - **Node.js**: Restart PM2 process
   - **React**: No restart needed (static files)

### 11. **Cleanup Old Releases**
   - Keep last 5 releases (for rollback)
   - Delete older releases to save space

## 🔄 Different Backends, Different Steps

### Laravel Deployment:
```bash
1. Clone code
2. composer install
3. Link .env and storage
4. php artisan config:cache
5. php artisan route:cache
6. php artisan migrate (if needed)
7. Update symlink
8. Reload PHP-FPM
```

### Node.js Deployment:
```bash
1. Clone code
2. npm install
3. Link .env
4. Update symlink
5. PM2 restart myapp
```

### React Deployment:
```bash
1. Clone code
2. npm install
3. npm run build
4. Update symlink (point to build folder)
5. Done! (no service restart needed)
```

## 🛡️ Safety Features

### 1. **Pre-Deployment Checks**
   - Project exists?
   - Git accessible?
   - Enough disk space?
   - Current version working?

### 2. **Rollback Capability**
   - Keep old releases
   - Can instantly rollback if something breaks
   - Just update symlink back to old release

### 3. **Error Handling**
   - If any step fails, stop deployment
   - Keep current version running
   - Show clear error messages

### 4. **Backup Before Changes**
   - Backup current .env (just in case)
   - Can restore if needed

## 📝 Usage Examples

### Deploy from Git (first time):
```bash
./bin/deploy.sh myapp https://github.com/user/myapp.git
```

### Deploy update (pull latest):
```bash
./bin/deploy.sh myapp
```

### Deploy specific branch:
```bash
./bin/deploy.sh myapp https://github.com/user/myapp.git main
```

### Deploy specific tag:
```bash
./bin/deploy.sh myapp https://github.com/user/myapp.git v1.2.3
```

## 🔄 Rollback Process

If something breaks:

```bash
./bin/rollback.sh myapp
```

This will:
1. List available releases
2. Ask which to rollback to
3. Update symlink to old release
4. Restart services
5. Done! (instant rollback)

## 🎯 Key Concepts

### 1. **Release Folders**
   - Each deployment = new folder
   - Keep multiple versions
   - Easy to compare/rollback

### 2. **Shared Folder**
   - `.env` - Environment config (not in Git)
   - `storage/` - User uploads, logs (persist)
   - Symlinked to each release

### 3. **Atomic Symlink Update**
   - `ln -sfn` is atomic
   - No gap between old and new
   - Zero downtime!

### 4. **Service Restart**
   - PHP-FPM: Reload (graceful, keeps connections)
   - Node.js: PM2 restart (quick restart)
   - React: No restart (static files)

---

**Ready to see the actual script?**
