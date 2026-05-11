#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

BACKUP_DIR="/root/pgsql_backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_DIR/$DATE"

LOG_FILE="/var/log/pgsql_backup.log"

mkdir -p "$BACKUP_PATH"

# Logging
exec >> "$LOG_FILE" 2>&1

echo "Backup started at $(date)"

FAILED_DBS=()
SUCCESS_DBS=()

# Get DB list (as postgres user)
DATABASES=$(sudo -u postgres psql -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;")

for DB in $DATABASES
do
    echo "Backing up: $DB"

    sudo -u postgres pg_dump -F c "$DB" | gzip > "$BACKUP_PATH/$DB.dump.gz"

    if [ $? -eq 0 ]; then
        echo "[OK] $DB compressed backup created"
        SUCCESS_DBS+=("$DB")
    else
        echo "[FAILED] $DB"
        FAILED_DBS+=("$DB")
    fi
done

echo "Backup completed at $(date)"

# Cleanup old backups
find "$BACKUP_DIR" -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"

# Email logic
if [ ${#FAILED_DBS[@]} -ne 0 ]; then
    SUBJECT="🚨 PostgreSQL Backup FAILED on $HOST"

    BODY="Backup completed with errors.\n\nFailed Databases:\n"

    for DB in "${FAILED_DBS[@]}"
    do
        BODY="$BODY - $DB\n"
    done
else
    SUBJECT="✅ PostgreSQL Backup SUCCESS on $HOST"

    BODY="All databases backed up successfully.\n\nBacked up Databases:\n"

    for DB in "${SUCCESS_DBS[@]}"
    do
        BODY="$BODY - $DB\n"
    done
fi

BODY="$BODY\nBackup Location: $BACKUP_PATH\nLog file: $LOG_FILE\nTime: $(date)"

echo -e "$BODY" | mail -s "$SUBJECT" "$EMAIL"

echo "Backup script finished"
~
