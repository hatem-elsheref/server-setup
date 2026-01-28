# Why Multiple Linux Users? (Simple Explanation)

## 🤔 The Question

"Why can't we just use ONE user (like `www-data` or `deploy`) for all projects?"

## ✅ Short Answer

**Security and isolation.** If one project gets hacked, the attacker can't access other projects.

## 📚 Detailed Explanation (Simple)

### Scenario 1: ONE User for Everything (BAD)

```
All projects owned by: www-data

/infra/projects/project1/  → owned by www-data
/infra/projects/project2/  → owned by www-data
/infra/projects/project3/  → owned by www-data
```

**What happens if Project1 gets hacked?**

1. Attacker gains access to Project1's files
2. Since Project1 runs as `www-data`
3. Attacker can now READ/WRITE Project2 and Project3 files! 😱
4. Attacker can steal databases, modify code, delete everything

**Why?** Because Linux permissions: if you own the files, you can do anything.

---

### Scenario 2: Multiple Users (GOOD)

```
Project1 owned by: project1_user
Project2 owned by: project2_user
Project3 owned by: project3_user
```

**What happens if Project1 gets hacked?**

1. Attacker gains access to Project1's files
2. Project1 runs as `project1_user`
3. Attacker tries to access Project2 files
4. **Permission denied!** ❌
5. `project1_user` cannot read `project2_user` files
6. Other projects are SAFE! ✅

---

## 🔒 Real-World Example

### Without User Isolation:

```bash
# Attacker in Project1 can do:
cd /infra/projects/project2/
cat .env  # Steal database credentials!
rm -rf *  # Delete everything!
```

### With User Isolation:

```bash
# Attacker in Project1 tries:
cd /infra/projects/project2/
cat .env
# Permission denied! (not the owner)
```

---

## 🛡️ Additional Benefits

### 1. **Process Isolation**
- Each project's processes run as its own user
- If Project1's PHP crashes, it can't affect Project2's processes
- Better resource tracking (see which user is using CPU/memory)

### 2. **File Permissions**
- Clear ownership: "This file belongs to Project1"
- Easy to fix permissions: `chown -R project1_user:project1_user /infra/projects/project1/`
- No accidental cross-project file access

### 3. **Database Security**
- Each user can only access their own database
- MySQL user: `project1_user` → can only access `project1_db`
- Even if credentials leak, damage is limited

### 4. **Logging & Auditing**
- System logs show: "project1_user did X"
- Easy to track which project caused an issue
- Better debugging

---

## 🏠 Apartment Building Analogy

**One User (Bad):**
- Everyone has the master key
- If one tenant loses their key, everyone's apartments are at risk

**Multiple Users (Good):**
- Each tenant has their own key
- If one tenant loses their key, only their apartment is at risk
- Other tenants are safe

---

## 💻 How It Works in Practice

### When We Create a Project:

```bash
# Script creates:
1. Linux user: project1_user
2. User ID (UID): 10001
3. Group: project1_user
4. Home directory: /infra/projects/project1/
5. Files owned by: project1_user:project1_user
```

### When Project Runs:

```bash
# PHP-FPM runs as:
User: project1_user
Group: project1_user

# Node.js runs as:
User: project1_user
Group: project1_user

# Files created by app:
Owner: project1_user
Permissions: 644 (readable by web server, writable by owner)
```

---

## ⚠️ Common Misconception

**"But I trust my projects, why do I need this?"**

Even if you trust your code:
- **Third-party packages** might have vulnerabilities
- **Configuration mistakes** can expose files
- **Future projects** might be less secure
- **Best practice** = defense in depth

It's like wearing a seatbelt even if you're a good driver.

---

## 🎯 Summary

| Aspect | One User | Multiple Users |
|--------|----------|----------------|
| **Security** | ❌ One hack = all projects at risk | ✅ One hack = only that project |
| **Isolation** | ❌ Projects can access each other | ✅ Projects are isolated |
| **Debugging** | ❌ Hard to track which project | ✅ Clear ownership |
| **Permissions** | ❌ Complex, error-prone | ✅ Simple, clear |
| **Best Practice** | ❌ Not recommended | ✅ Industry standard |

---

## 🤔 Still Confused?

Think of it like this:
- **One user** = Everyone shares the same bank account (dangerous!)
- **Multiple users** = Everyone has their own bank account (safe!)

---

**Does this make sense now?** 

The extra complexity is worth it for the security benefits. And our scripts will handle all the user creation automatically - you won't have to think about it!
