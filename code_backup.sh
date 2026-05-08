#!/bin/bash


EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

BACKUP_BASE="/root/code_backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_BASE/$DATE"

LOG_FILE="/var/log/code_backup.log"

S3_BUCKET="s3://arindam-dev-backup/Code_backup"

SRC_HOME="/home"
SRC_WWW="/var/www/html"


mkdir -p "$BACKUP_PATH"

exec >> "$LOG_FILE" 2>&1

echo "Code Backup started at $(date)"

FAILED_ITEMS=()
SUCCESS_ITEMS=()


echo "Processing /home users..."

for USER_DIR in "$SRC_HOME"/*
do
    [ -d "$USER_DIR" ] || continue

    USERNAME=$(basename "$USER_DIR")

    # Skip system users
    [[ "$USERNAME" == "root" || "$USERNAME" == "ubuntu" ]] && continue

    echo "Checking user: $USERNAME"

    if [ -d "$USER_DIR/public_html" ]; then
        BASE_PATH="$USER_DIR"
        TARGET="public_html"
    elif [ -d "$USER_DIR/Public_html" ]; then
        BASE_PATH="$USER_DIR"
        TARGET="Public_html"
    else
        BASE_PATH="$SRC_HOME"
        TARGET="$USERNAME"
    fi

    tar -czf "$BACKUP_PATH/${USERNAME}.tar.gz" \
        --exclude='node_modules' \
        --exclude='vendor' \
        --exclude='.git' \
        --exclude='.cache' \
        --exclude='.npm' \
        --exclude='.config' \
        --exclude='.local' \
        --exclude='*.log' \
        -C "$BASE_PATH" "$TARGET"

    if [ $? -eq 0 ]; then
        echo "[OK] $USERNAME"
        SUCCESS_ITEMS+=("$USERNAME")
    else
        echo "[FAILED] $USERNAME"
        FAILED_ITEMS+=("$USERNAME")
    fi

done


echo "Processing /var/www/html..."

for PROJECT in "$SRC_WWW"/*
do
    [ -d "$PROJECT" ] || continue

    NAME=$(basename "$PROJECT")

    echo "Backing up project: $NAME"

    tar -czf "$BACKUP_PATH/${NAME}.tar.gz" \
        --exclude='node_modules' \
        --exclude='vendor' \
        --exclude='.git' \
        --exclude='.cache' \
        --exclude='*.log' \
        -C "$SRC_WWW" "$NAME"

    if [ $? -eq 0 ]; then
        echo "[OK] $NAME"
        SUCCESS_ITEMS+=("$NAME")
    else
        echo "[FAILED] $NAME"
        FAILED_ITEMS+=("$NAME")
    fi

done

echo "Compression completed"


echo "Uploading to S3..."

aws s3 cp "$BACKUP_PATH" "$S3_BUCKET/$DATE/" \
    --recursive \
    --storage-class STANDARD_IA \
    --sse AES256

if [ $? -eq 0 ]; then
    echo "[OK] S3 Upload"
else
    echo "[FAILED] S3 Upload"
    FAILED_ITEMS+=("S3_UPLOAD")
fi


find "$BACKUP_BASE" -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"


TOTAL_SUCCESS=${#SUCCESS_ITEMS[@]}
TOTAL_FAILED=${#FAILED_ITEMS[@]}

SUBJECT="📦 Code Backup Report on $HOST"

BODY="Code Backup Report\n"
BODY="$BODY=================================\n"
BODY="$BODY Server: $HOST\n"
BODY="$BODY Date: $(date)\n\n"

BODY="$BODY Successful Backups ($TOTAL_SUCCESS):\n"
for ITEM in "${SUCCESS_ITEMS[@]}"
do
    BODY="$BODY  ✔ $ITEM\n"
done

BODY="$BODY\nFailed Backups ($TOTAL_FAILED):\n"
if [ $TOTAL_FAILED -eq 0 ]; then
    BODY="$BODY  None 🎉\n"
else
    for ITEM in "${FAILED_ITEMS[@]}"
    do
        BODY="$BODY  ✖ $ITEM\n"
    done
fi

BODY="$BODY\nBackup Path: $BACKUP_PATH\n"
BODY="$BODY S3 Location: $S3_BUCKET/$DATE/\n"
BODY="$BODY Log File: $LOG_FILE\n"

echo -e "$BODY" | mail -s "$SUBJECT" "$EMAIL"

echo "Code backup finished at $(date)"
