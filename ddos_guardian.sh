#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

CONNECTION_THRESHOLD=15
HIGH_THRESHOLD=30
BLOCK_TIME=86400        # 1 DAY
ALERT_COOLDOWN=60      # 10 minutes

LOG="/var/log/ddos_guardian.log"
BLACKLIST="/var/log/ddos_blacklist.txt"
WHITELIST="/etc/ddos_whitelist.txt"

APACHE_LOG="/var/log/apache2/access.log"

IPSET="ddos_blocklist"
ALERT_CACHE="/tmp/ddos_alert_cache.txt"

# =========================
# INIT FILES
# =========================
touch $ALERT_CACHE
touch $BLACKLIST
touch $WHITELIST

# =========================
# INIT FIREWALL
# =========================
ipset list $IPSET >/dev/null 2>&1 || ipset create $IPSET hash:ip timeout $BLOCK_TIME

iptables -C INPUT -m set --match-set $IPSET src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set $IPSET src -j DROP

echo "$(date) - DDOS Guardian v4 started" >> $LOG

# =========================
# FUNCTION: WHITELIST CHECK
# =========================
is_whitelisted() {
    grep -w "$1" $WHITELIST >/dev/null 2>&1
}

# =========================
# MAIN LOOP
# =========================
while true
do
    # 🔍 GET TOP IP
    TOP=$(ss -ntu state established '( sport = :80 or sport = :443 )' \
    | awk 'NR>1 {print $5}' \
    | sed 's/\[//g' | sed 's/\]//g' \
    | awk -F: '{print $(NF-1)}' \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -nr | head -n1)

    COUNT=$(echo "$TOP" | awk '{print $1}')
    IP=$(echo "$TOP" | awk '{print $2}')

    # Skip invalid
    [[ -z "$IP" || -z "$COUNT" ]] && sleep 10 && continue

    # Skip whitelist
    if is_whitelisted "$IP"; then
        sleep 10
        continue
    fi

    # =========================
    # APACHE ANALYSIS
    # =========================
    LOG_SAMPLE=$(tail -n 2000 $APACHE_LOG)

    TOP_URLS=$(echo "$LOG_SAMPLE" | awk '{print $7}' | sort | uniq -c | sort -nr | head -n 3)
    TOP_UA=$(echo "$LOG_SAMPLE" | awk -F\" '{print $6}' | sort | uniq -c | sort -nr | head -n1)

    URL_MAIN=$(echo "$TOP_URLS" | head -n1 | awk '{print $2}')
    UA=$(echo "$TOP_UA" | cut -d' ' -f2-)

    # =========================
    # FRAMEWORK DETECTION
    # =========================
    FRAMEWORK="UNKNOWN"
    [[ "$URL_MAIN" == *"/wp-"* ]] && FRAMEWORK="WordPress"
    [[ "$URL_MAIN" == *"/api/"* ]] && FRAMEWORK="Node/Next.js API"
    [[ "$URL_MAIN" == *".php"* ]] && FRAMEWORK="PHP"
    [[ "$URL_MAIN" == *"/admin"* ]] && FRAMEWORK="Admin Panel"

    # =========================
    # ATTACK LEVEL
    # =========================
    SUBJECT=""
    ICON=""

    if [ "$COUNT" -ge "$HIGH_THRESHOLD" ]; then
        SUBJECT="🔥 CRITICAL DDOS $HOST"
        ICON="🚨"
    elif [ "$COUNT" -ge "$CONNECTION_THRESHOLD" ]; then
        SUBJECT="  DDOS ALERT $HOST"
        ICON=" "
    else
        sleep 10
        continue
    fi

    # =========================
    # BLOCK LOGIC
    # =========================
    if ! ipset test $IPSET $IP >/dev/null 2>&1; then
        ipset add $IPSET $IP timeout $BLOCK_TIME
        echo "$IP" >> $BLACKLIST
        ACTION="BLOCKED (1 DAY)"
    else
        ACTION="REPEAT ATTACK (ALREADY BLOCKED)"
    fi

    # =========================
    # SMART ALERT CONTROL
    # =========================
    CURRENT_TIME=$(date +%s)
    LAST_ALERT_TIME=$(grep "^$IP " $ALERT_CACHE | awk '{print $2}')

    SEND_ALERT=false

    if [ -z "$LAST_ALERT_TIME" ]; then
        SEND_ALERT=true
    else
        DIFF=$((CURRENT_TIME - LAST_ALERT_TIME))
        if [ "$DIFF" -ge "$ALERT_COOLDOWN" ]; then
            SEND_ALERT=true
        fi
    fi

    # =========================
    # SEND MAIL
    # =========================
    if [ "$SEND_ALERT" = true ]; then

        MESSAGE=$(cat <<EOF
$ICON DDOS ALERT

Server: $HOST

Attacker IP: $IP
Connections: $COUNT

Framework: $FRAMEWORK

Top URLs:
$TOP_URLS

User-Agent:
$UA

Action: $ACTION
EOF
)

        echo "$MESSAGE" | mail -s "$SUBJECT" $EMAIL
        echo "$(date) - $MESSAGE" >> $LOG

        # Update cache
        grep -v "^$IP " $ALERT_CACHE > ${ALERT_CACHE}.tmp
        echo "$IP $CURRENT_TIME" >> ${ALERT_CACHE}.tmp
        mv ${ALERT_CACHE}.tmp $ALERT_CACHE
    fi

    sleep 10
done
~
~
