# Simple Example: Why Multiple Users Matter

## 🎬 Scenario: You Have 3 Projects

### Project Setup:
- **Project1**: Your main Laravel app (trusted)
- **Project2**: Client's WordPress site (less trusted)
- **Project3**: Experimental Node.js app (testing)

---

## ❌ WITHOUT Multiple Users (Dangerous)

```bash
# All projects run as: www-data

$ ls -la /infra/projects/
drwxr-xr-x  www-data www-data  project1/
drwxr-xr-x  www-data www-data  project2/
drwxr-xr-x  www-data www-data  project3/
```

**What happens if Project2 (WordPress) gets hacked?**

```bash
# Attacker can now:
cd /infra/projects/project1/
cat .env  # ✅ SUCCESS! Stole your database password!

cd /infra/projects/project3/
rm -rf *  # ✅ SUCCESS! Deleted your experimental app!

# Attacker has access to EVERYTHING
```

**Result:** One vulnerable project = ALL projects compromised 😱

---

## ✅ WITH Multiple Users (Safe)

```bash
# Each project has its own user

$ ls -la /infra/projects/
drwxr-xr-x  project1_user project1_user  project1/
drwxr-xr-x  project2_user project2_user  project2/
drwxr-xr-x  project3_user project3_user  project3/
```

**What happens if Project2 (WordPress) gets hacked?**

```bash
# Attacker tries:
cd /infra/projects/project1/
cat .env
# ❌ Permission denied! (not the owner)

cd /infra/projects/project3/
rm -rf *
# ❌ Permission denied! (not the owner)

# Attacker is STUCK in Project2 only
```

**Result:** One vulnerable project = Only that project affected ✅

---

## 🔍 Real Permission Check

### Without Isolation:
```bash
$ whoami
www-data

$ cat /infra/projects/project1/.env
DB_PASSWORD=secret123  # ✅ Can read!

$ cat /infra/projects/project2/.env
DB_PASSWORD=another_secret  # ✅ Can read!

# www-data owns everything = can read everything
```

### With Isolation:
```bash
$ whoami
project2_user

$ cat /infra/projects/project1/.env
cat: .env: Permission denied  # ❌ Cannot read!

$ cat /infra/projects/project2/.env
DB_PASSWORD=another_secret  # ✅ Can read (owns it)

# project2_user only owns project2 = can only read project2
```

---

## 💡 Think of It Like This

**One User = Shared Apartment Key**
- Everyone has the same key
- If someone loses it, everyone's stuff is at risk

**Multiple Users = Individual Keys**
- Each person has their own key
- If someone loses it, only their stuff is at risk

---

**Does this help clarify why we need multiple users?**
