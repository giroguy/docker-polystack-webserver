#!/bin/bash
set -euo pipefail

# Load env
source /srv/server/.env

# ─── Config ────────────────────────────────────────────────────────────────
DATE=$(date +%Y-%m-%d)
LOCAL_BACKUP_DIR="/srv/backups/$DATE"

# Remote destination — any SSH-accessible server (NAS, VPS, etc.)
REMOTE_HOST="your-remote-host"          # hostname, IP, or Tailscale address
REMOTE_USER="your-remote-user"
REMOTE_PATH="/path/to/backups"          # destination path on remote server
SSH_KEY="/root/.ssh/backup_key"         # SSH key for remote access
KEEP_DAYS=7
# ───────────────────────────────────────────────────────────────────────────

mkdir -p "$LOCAL_BACKUP_DIR"

# Dump all user databases (skips system DBs automatically)
DATABASES=$(docker exec mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
  "SHOW DATABASES;" --skip-column-names 2>/dev/null \
  | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")

for DB in $DATABASES; do
  echo "Dumping $DB..."
  docker exec mysql mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
    --single-transaction --quick "$DB" 2>/dev/null \
    | gzip > "$LOCAL_BACKUP_DIR/$DB.sql.gz"
done

# Sync to remote
echo "Syncing to $REMOTE_HOST..."
rsync -az --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_BACKUP_DIR/" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/$DATE/"

# Prune local backups older than KEEP_DAYS
find /srv/backups -maxdepth 1 -type d -mtime +$KEEP_DAYS -exec rm -rf {} +

# Prune remote backups older than KEEP_DAYS
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" \
  "find \"$REMOTE_PATH\" -maxdepth 1 -type d -mtime +$KEEP_DAYS -exec rm -rf {} +"

echo "Backup complete: $DATE"
