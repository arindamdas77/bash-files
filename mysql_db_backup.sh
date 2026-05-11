

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

BACKUP_DIR="/root/mysql_backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_DIR/$DATE"

LOG_FILE="/var/log/mysql_backup.log"

mkdir -p "$BACKUP_PATH"

exec >> "$LOG_FILE" 2>&1

echo "=============================="
echo "Backup started at $(date)"
echo "=============================="

FAILED_DBS=()
SUCCESS_DBS=()

SUCCESS_COUNT=0
TOTAL_COUNT=0

DATABASES=$(mysql -N -e "SHOW DATABASES;" | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")

echo ""
echo "Database List:"
echo "------------------------------"

for DB in $DATABASES
do
    echo " - $DB"
done

echo "------------------------------"
echo ""

for DB in $DATABASES
do
    TOTAL_COUNT=$((TOTAL_COUNT+1))

    echo "Backing up: $DB"

    mysqldump --single-transaction --quick --skip-lock-tables --force "$DB" > "$BACKUP_PATH/$DB.sql"

    if [ -s "$BACKUP_PATH/$DB.sql" ]; then

        gzip "$BACKUP_PATH/$DB.sql"

        SUCCESS_DBS+=("$DB")

        SUCCESS_COUNT=$((SUCCESS_COUNT+1))

        echo "[OK] $DB"

    else

        FAILED_DBS+=("$DB")

        echo "[FAILED] $DB"

        rm -f "$BACKUP_PATH/$DB.sql"

    fi
done

echo ""
echo "Backup completed at $(date)"

find "$BACKUP_DIR" -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"

# ================= EMAIL =================

FAILED_COUNT=${#FAILED_DBS[@]}

BODY="Backup Summary:\n\n"

BODY="$BODY Total DBs: $TOTAL_COUNT\n"
BODY="$BODY Successful: $SUCCESS_COUNT\n"
BODY="$BODY Failed: $FAILED_COUNT\n\n"

BODY="$BODY Successful Databases:\n"

for DB in "${SUCCESS_DBS[@]}"
do
    BODY="$BODY ✔ $DB\n"
done

BODY="$BODY\n"

if [ $FAILED_COUNT -ne 0 ]; then

    SUBJECT="MySQL Backup FAILED on $HOST"

    BODY="$BODY Failed Databases:\n"

    for DB in "${FAILED_DBS[@]}"
    do
        BODY="$BODY ✖ $DB\n"
    done

else

    SUBJECT="MySQL Backup SUCCESS on $HOST"

fi

BODY="$BODY\nBackup Path: $BACKUP_PATH\n"
BODY="$BODY\nTime: $(date)\n"

echo -e "$BODY" | /usr/bin/mail -s "$SUBJECT" "$EMAIL"

echo ""
echo "=============================="
echo "Backup Summary"
echo "=============================="

echo "Total DBs: $TOTAL_COUNT"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAILED_COUNT"

echo ""

echo "Successful Databases:"

for DB in "${SUCCESS_DBS[@]}"
do
    echo " ✔ $DB"
done

echo ""

if [ $FAILED_COUNT -ne 0 ]; then

    echo "Failed Databases:"

    for DB in "${FAILED_DBS[@]}"
    do
        echo " ✖ $DB"
    done

fi

echo ""
echo "Backup Path: $BACKUP_PATH"

echo ""
echo "=============================="
echo "Backup script finished"
echo "=============================="
