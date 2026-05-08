#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

BACKUP_DIR="/root/mysql_backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_DIR/$DATE"

LOG_FILE="/var/log/mysql_backup.log"

mkdir -p "$BACKUP_PATH"

exec >> "$LOG_FILE" 2>&1

echo "Backup started at $(date)"

FAILED_DBS=()
SUCCESS_COUNT=0
TOTAL_COUNT=0

DATABASES=$(mysql -N -e "SHOW DATABASES;" | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")

for DB in $DATABASES
do
    TOTAL_COUNT=$((TOTAL_COUNT+1))

    echo "Backing up: $DB"

    mysqldump --single-transaction --quick --skip-lock-tables --force "$DB" > "$BACKUP_PATH/$DB.sql"

    if [ -s "$BACKUP_PATH/$DB.sql" ]; then
        gzip "$BACKUP_PATH/$DB.sql"
        SUCCESS_COUNT=$((SUCCESS_COUNT+1))
        echo "[OK] $DB"
    else
        FAILED_DBS+=("$DB")
        echo "[FAILED] $DB"
    fi
done

echo "Backup completed at $(date)"

find "$BACKUP_DIR" -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"

# Email

BODY="Backup Summary:\n\n"
BODY="$BODY Total DBs: $TOTAL_COUNT\n"
BODY="$BODY Successful: $SUCCESS_COUNT\n"
BODY="$BODY Failed: ${#FAILED_DBS[@]}\n\n"

if [ ${#FAILED_DBS[@]} -ne 0 ]; then
    SUBJECT="MySQL Backup FAILED on $HOST"

    BODY="$BODY Failed Databases:\n"
    for DB in "${FAILED_DBS[@]}"
    do
        BODY="$BODY - $DB\n"
    done
else
    SUBJECT="MySQL Backup SUCCESS on $HOST"
fi

BODY="$BODY\nBackup Path: $BACKUP_PATH\n"
BODY="$BODY Time: $(date)"

echo -e "$BODY" | /usr/bin/mail -s "$SUBJECT" "$EMAIL"

echo "Backup script finished"
