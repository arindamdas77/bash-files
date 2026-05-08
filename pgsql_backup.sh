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

echo "PostgreSQL Backup Started: $(date)"
echo "Host: $HOST"
echo "Backup Path: $BACKUP_PATH"

FAILED_DBS=()
SUCCESS_DBS=()

# Get all databases except templates
DATABASES=$(sudo -u postgres psql -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;")

for DB in $DATABASES
do
    echo ""
    echo "-------------------------------------"
    echo "Backing up database: $DB"
    echo "-------------------------------------"

    # 1. CUSTOM FORMAT DUMP (.dump.gz)

    echo "Creating .dump.gz backup..."

    sudo -u postgres pg_dump \
        -F c \
        "$DB" | gzip > "$BACKUP_PATH/$DB.dump.gz"

    if [ $? -eq 0 ]; then
        echo "[OK] .dump.gz backup created"
    else
        echo "[FAILED] .dump.gz backup failed"
        FAILED_DBS+=("$DB")
        continue
    fi

    # 2. PLAIN SQL BACKUP (.sql.gz)

    echo "Creating .sql.gz backup..."

    sudo -u postgres pg_dump \
        --clean \
        --if-exists \
        --create \
        "$DB" | gzip > "$BACKUP_PATH/$DB.sql.gz"

    if [ $? -eq 0 ]; then
        echo "[OK] .sql.gz backup created"
        SUCCESS_DBS+=("$DB")
    else
        echo "[FAILED] .sql.gz backup failed"
        FAILED_DBS+=("$DB")
    fi
done

echo ""
echo "Backup Completed: $(date)"

# Cleanup backups older than 7 days
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"

echo ""
echo "Successful Databases:"
for DB in "${SUCCESS_DBS[@]}"
do
    echo " - $DB"
done

echo ""
echo "Failed Databases:"
for DB in "${FAILED_DBS[@]}"
do
    echo " - $DB"
done

# EMAIL SUMMARY

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

BODY="$BODY\n\nBackup Location: $BACKUP_PATH"
BODY="$BODY\nLog File: $LOG_FILE"
BODY="$BODY\nBackup Time: $(date)"

echo -e "$BODY" | mail -s "$SUBJECT" "$EMAIL"

echo ""
echo "Backup script finished successfully"
