# PHASE 1: Architecture Overview

## 🏗️ What We're Building (Simple Explanation)

Think of this like a **shared apartment building** where:
- Each **project** is a **tenant** (gets their own room/subdomain)
- **Shared services** are the building's utilities (water, electricity = databases, Redis, etc.)
- **Nginx** is the **doorman** - it routes visitors to the right apartment
- **Scripts** are the **building manager** - they automate everything

## 🧠 Mental Model for Backend Developers

### Traditional Development:
```
Your laptop → Run project → localhost:3000
```

### Our PaaS System:
```
Internet → Nginx (doorman) → Routes to project folder → Your app runs
```

### Key Concepts:

1. **Subdomain Mapping**
   - `project1.yourdomain.com` → `/infra/projects/project1/`
   - `project2.yourdomain.com` → `/infra/projects/project2/`
   - Nginx reads a config file and says "Oh, project1.yourdomain.com? Go to that folder!"

2. **Shared Services**
   - MySQL, Redis, etc. run ONCE on the server
   - All projects connect to the SAME services
   - Each project gets its own DATABASE (but same MySQL server)
   - Like: One building, many apartments, shared utilities

3. **Port Management**
   - We use a `ports.map` file to track which ports are used
   - Prevents conflicts (no random ports!)
   - Example: Project1 uses port 8001, Project2 uses 8002

4. **User Isolation**
   - Each project gets a Linux user (for security)
   - Files owned by that user (permissions)
   - Like: Each tenant has their own key

5. **PHP Version Management**
   - Multiple PHP versions installed (7.4, 8.0, 8.1, 8.2, 8.3)
   - Each project can choose its version
   - PHP-FPM handles the execution (like a worker pool)

## 📁 Folder Structure (Why Each Exists)

```
/infra
  /bin              → Your CLI tools (like npm scripts, but for infrastructure)
                      Example: `./bin/create-project` runs the project creation
  
  /templates        → Reusable config files (like .env.example files)
                      Nginx configs, Supervisor configs, etc.
                      We copy these and fill in project-specific values
  
  /services         → Shared services configuration
                      Where we store service configs (MySQL, Redis, etc.)
                      Not project-specific, server-wide
  
  /projects         → All your applications live here
                      Each project = one folder
                      /projects/project1/
                      /projects/project2/
  
  /logs             → Centralized logging
                      All project logs go here
                      Easy to debug issues
  
  ports.map         → Simple text file tracking port usage
                      Format: project1:8001, project2:8002
                      Prevents conflicts
  
  users.map         → Tracks which Linux user owns which project
                      Format: project1:user1, project2:user2
                      Security & permissions
```

## 🔄 How It Works (The Flow)

### When You Create a Project:

1. **Script asks questions:**
   - Project name?
   - Domain?
   - Backend type? (Laravel/Node)
   - Database type? (MySQL/PostgreSQL/MongoDB)
   - PHP version? (if Laravel)

2. **Script does magic:**
   - Creates folder: `/infra/projects/myproject/`
   - Creates Linux user: `myproject`
   - Creates database: `myproject_db`
   - Generates Nginx config from template
   - Sets permissions
   - Updates `ports.map` and `users.map`

3. **You deploy:**
   - Git clone into project folder
   - Script runs `composer install` or `npm install`
   - Script sets up environment
   - Nginx reloads
   - Done!

### When Someone Visits Your Site:

1. Request comes to: `myproject.yourdomain.com`
2. Nginx checks its configs
3. Finds: "myproject.yourdomain.com → /infra/projects/myproject/public"
4. If Laravel: Routes to PHP-FPM (correct PHP version)
5. If Node: Routes to Node process (on assigned port)
6. Response sent back

## 🛡️ Security Basics (Simple)

- **User Isolation**: Each project runs as its own user (can't access other projects)
- **File Permissions**: Only project owner can modify files
- **Database Isolation**: Each project has separate database
- **Firewall**: Only ports we need are open

## 🎯 What Makes This "Lightweight"

- **No Docker**: Direct installation (faster, simpler)
- **No Kubernetes**: Single server, no orchestration needed
- **Script-based**: Everything is bash scripts (readable, editable)
- **Native**: Uses system packages (apt, not containers)

## ✅ Why This Structure Works

1. **Modular**: Each script does ONE thing
2. **Safe to Re-run**: Scripts check "does this exist?" before creating
3. **Readable**: Clear folder names, simple logic
4. **Maintainable**: Easy to find and fix issues

---

## 🤔 Questions to Check Understanding

Before we move to Phase 2, make sure you understand:

1. **Why subdomains?** → Each project needs a unique URL
2. **Why shared services?** → Don't need 10 MySQL servers, just 10 databases
3. **Why Linux users?** → Security (projects can't access each other)
4. **Why templates?** → Don't write Nginx configs from scratch every time
5. **Why ports.map?** → Track which ports are used (prevent conflicts)

---

**Ready for Phase 2?** (Creating the actual folder structure)
