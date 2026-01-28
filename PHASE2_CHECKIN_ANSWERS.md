# Phase 2 Check-in Answers

## ✅ Understanding Confirmed

1. **Symlinks for `current/`**: Understood - enables zero-downtime deployments by atomically switching the symlink to point to the latest release.

2. **sites-available vs sites-enabled**: Understood - sites-available contains all configs, sites-enabled contains symlinks to active configs (Nginx only serves enabled sites).

3. **releases/ vs shared/**: Understood - releases/ contains code versions, shared/ contains persistent files (.env, uploads) that survive deployments.

4. **Structure questions**: None - ready to proceed.

---

**Status**: Ready for Phase 3 - Server Initialization Script
