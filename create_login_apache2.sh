#!/bin/bash

HTPASSWD_FILE="/etc/apache2/.htpasswd"

# Must be root
if [ "$EUID" -ne 0 ]; then
  echo "Run as root or with sudo"
  exit 1
fi

# Ask username
read -p "Enter username: " USERNAME

# Generate strong password
PASSWORD=$(openssl rand -base64 9)

# Create htpasswd file if not exists
if [ ! -f "$HTPASSWD_FILE" ]; then
  touch "$HTPASSWD_FILE"
  chown root:www-data "$HTPASSWD_FILE"
  chmod 640 "$HTPASSWD_FILE"
fi

# Add or update user (no prompt)
htpasswd -b "$HTPASSWD_FILE" "$USERNAME" "$PASSWORD"

# Output result
echo
echo " Apache Auth User Credentials"
echo "=================================="
echo "Username : $USERNAME"
echo "Password : $PASSWORD"

