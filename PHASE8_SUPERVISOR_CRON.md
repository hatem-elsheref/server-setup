# PHASE 8: Supervisor & Cron Setup

## 🎯 What This Phase Does

This phase sets up **background process management** and **scheduled tasks** for your projects.

**Think of it as:** Workers that run in the background, doing jobs while your main app handles web requests.

## 🔄 Background Processes (Simple Explanation)

### The Problem:

Your web app handles HTTP requests, but some tasks take too long:
- Sending 1000 emails
- Processing large images
- Generating reports
- WebSocket connections (Socket.IO)

**If you do this in a web request:**
- User clicks "Send email"
- Server processes for 30 seconds
- User waits... and waits... ❌

### The Solution:

**Queue System:**
1. User clicks "Send email"
2. Job added to queue (instant response)
3. Background worker processes job
4. User gets immediate response ✅

## 📦 What is Supervisor?

**Supervisor** = Process manager that:
- Keeps processes running (auto-restart if they crash)
- Manages multiple workers
- Logs output
- Easy to start/stop/restart

### Common Use Cases:

1. **Laravel Queues**
   - Process background jobs
   - Send emails, process images, etc.
   - Multiple workers for speed

2. **Socket.IO Server**
   - Real-time communication
   - WebSocket connections
   - Must stay running

3. **Custom Workers**
   - Any long-running process
   - Data processing
   - API integrations

## ⏰ What is Cron?

**Cron** = Scheduled task runner that:
- Runs commands at specific times
- Daily, weekly, monthly, etc.
- Perfect for maintenance tasks

### Common Use Cases:

1. **Laravel Scheduler**
   - Run scheduled tasks
   - Cleanup old data
   - Send daily reports

2. **Backup Tasks**
   - Daily database backups
   - File backups
   - Cleanup old backups

3. **Maintenance**
   - Clear caches
   - Update statistics
   - Send notifications

## 🔧 How Supervisor Works

### Configuration File:
```ini
[program:myapp_queue]
command=php /infra/projects/myapp/current/artisan queue:work
directory=/infra/projects/myapp/current
user=myapp_user
autostart=true
autorestart=true
numprocs=2
```

**What this does:**
- Runs `php artisan queue:work`
- As user `myapp_user`
- Auto-starts on boot
- Auto-restarts if crashes
- Runs 2 workers (parallel processing)

### Supervisor Commands:
```bash
supervisorctl start myapp_queue    # Start workers
supervisorctl stop myapp_queue     # Stop workers
supervisorctl restart myapp_queue  # Restart workers
supervisorctl status               # See all processes
```

## ⏰ How Cron Works

### Cron Syntax:
```
* * * * * command
│ │ │ │ │
│ │ │ │ └── Day of week (0-7, Sunday = 0 or 7)
│ │ │ └──── Month (1-12)
│ │ └────── Day of month (1-31)
│ └──────── Hour (0-23)
└────────── Minute (0-59)
```

### Examples:
```
0 2 * * *    # Every day at 2:00 AM
*/5 * * * *  # Every 5 minutes
0 0 * * 0    # Every Sunday at midnight
```

### Laravel Scheduler:
Laravel has a built-in scheduler that runs via cron:

```bash
# In crontab (runs every minute):
* * * * * cd /path/to/project && php artisan schedule:run >> /dev/null 2>&1
```

Then in Laravel's `app/Console/Kernel.php`:
```php
protected function schedule(Schedule $schedule)
{
    $schedule->command('emails:send')->daily();
    $schedule->command('reports:generate')->weekly();
}
```

## 📋 What the Scripts Do

### 1. `setup-supervisor.sh`
   - Creates Supervisor config for project
   - Supports Laravel queues
   - Supports Node.js workers
   - Supports custom commands
   - Starts and enables workers

### 2. `setup-cron.sh`
   - Sets up Laravel scheduler (cron entry)
   - Runs every minute
   - Executes Laravel scheduled tasks

## 🎯 Laravel Queue Setup

### What Gets Created:

1. **Supervisor Config:**
   ```
   /etc/supervisor/conf.d/myapp_queue.conf
   ```

2. **Queue Worker:**
   - Runs `php artisan queue:work`
   - Processes jobs from queue
   - Auto-restarts on failure

3. **Multiple Workers:**
   - Can run multiple workers
   - Faster processing
   - More parallel jobs

### How It Works:

```
User → Web App → Adds job to queue → Returns response
                                    ↓
                            Queue Worker → Processes job
```

## 🎯 Node.js Worker Setup

### What Gets Created:

1. **Supervisor Config:**
   ```
   /etc/supervisor/conf.d/myapp_node.conf
   ```

2. **Node Process:**
   - Runs `node server.js` or `npm start`
   - Keeps Socket.IO server running
   - Auto-restarts on failure

## ⏰ Laravel Scheduler Setup

### What Gets Created:

1. **Cron Entry:**
   ```
   * * * * * cd /infra/projects/myapp/current && php artisan schedule:run
   ```

2. **Laravel Tasks:**
   - Defined in `app/Console/Kernel.php`
   - Run automatically
   - Logged for debugging

## 🔄 Process Lifecycle

### Supervisor:
1. **Start:** Supervisor starts worker
2. **Running:** Worker processes jobs
3. **Crash:** Supervisor detects crash
4. **Restart:** Supervisor restarts worker
5. **Stop:** Supervisor stops worker gracefully

### Cron:
1. **Schedule:** Cron checks schedule every minute
2. **Match:** If time matches, run command
3. **Execute:** Run Laravel scheduler
4. **Laravel:** Laravel checks its schedule
5. **Tasks:** Run scheduled tasks

## 🛡️ Safety Features

1. **Auto-Restart**
   - Workers restart if they crash
   - No manual intervention needed

2. **Logging**
   - All output logged
   - Easy to debug issues

3. **User Isolation**
   - Workers run as project user
   - Can't access other projects

4. **Resource Limits**
   - Can limit CPU/memory
   - Prevents resource exhaustion

## 📝 Usage Examples

### Setup Laravel Queue:
```bash
./bin/setup-supervisor.sh myapp queue
```

### Setup Node.js Worker:
```bash
./bin/setup-supervisor.sh myapp node
```

### Setup Laravel Scheduler:
```bash
./bin/setup-cron.sh myapp
```

### Check Status:
```bash
supervisorctl status
```

### View Logs:
```bash
tail -f /infra/logs/projects/myapp/queue.log
```

## 🎯 Key Concepts

### 1. **Queue Workers**
   - Process background jobs
   - Run continuously
   - Auto-restart on failure

### 2. **Scheduled Tasks**
   - Run at specific times
   - Automated maintenance
   - No manual intervention

### 3. **Process Management**
   - Supervisor keeps processes alive
   - Auto-restart on crash
   - Easy to manage

### 4. **User Isolation**
   - Each project's workers run as project user
   - Can't interfere with other projects
   - Secure and isolated

---

**Ready to see the actual scripts?**
