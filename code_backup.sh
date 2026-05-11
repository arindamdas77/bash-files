#!/bin/bash

HOST=$(hostname)

EMAILS="arindam.das@maxbridgesolution.com"

BACKUP_BASE="/root/code_backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_BASE/$DATE"

LOG_FILE="/var/log/code_backup.log"

SRC_HOME="/home"
SRC_WWW="/var/www/html"

mkdir -p "$BACKUP_PATH"

exec >> "$LOG_FILE" 2>&1

echo "====================================="
echo "Code Backup started at $(date)"
echo "====================================="

FAILED_ITEMS=()
SUCCESS_ITEMS=()

# =====================================
# Backup /home users
# =====================================

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

# =====================================
# Backup /var/www/html projects
# =====================================

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
        --exclude='.npm' \
        --exclude='.config' \
        --exclude='.local' \
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

# =====================================
# Delete backups older than 7 days
# =====================================

find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "Old backups cleaned"

TOTAL_SUCCESS=${#SUCCESS_ITEMS[@]}
TOTAL_FAILED=${#FAILED_ITEMS[@]}

echo ""
echo "Code Backup Summary"
echo "Server: $HOST"
echo "Backup Path: $BACKUP_PATH"
echo "Date: $(date)"
echo ""

echo "Successful Backups ($TOTAL_SUCCESS):"

for ITEM in "${SUCCESS_ITEMS[@]}"
do
    echo "  [OK] $ITEM"
done

echo ""

echo "Failed Backups ($TOTAL_FAILED):"

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "  None"
else
    for ITEM in "${FAILED_ITEMS[@]}"
    do
        echo "  [FAILED] $ITEM"
    done
fi

echo ""
echo "Code backup finished at $(date)"

# Mail Report

MAIL_BODY=$(cat <<EOF
Code Backup Summary

Server: $HOST
Date: $(date)

Backup Location:
$BACKUP_PATH


Successful Backups ($TOTAL_SUCCESS):

$(for ITEM in "${SUCCESS_ITEMS[@]}"
do
    echo "[OK] $ITEM"
done)


Failed Backups ($TOTAL_FAILED):

$(if [ $TOTAL_FAILED -eq 0 ]; then
    echo "None"
else
    for ITEM in "${FAILED_ITEMS[@]}"
    do
        echo "[FAILED] $ITEM"
    done
fi)


Code backup finished at $(date)

EOF
)

echo "$MAIL_BODY" | mail -s "Code Backup Report - $HOST" "$EMAILS"

echo "Mail report sent"
~
