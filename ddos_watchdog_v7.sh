#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

CONNECTION_THRESHOLD=80
HIGH_THRESHOLD=150
DB_THRESHOLD=40
BLOCK_TIME=6000000

LOG="/var/log/ddos_watchdog.log"
BLACKLIST_FILE="/var/log/ddos_blacklist.txt"
WHITELIST_FILE="/var/log/ddos_whitelist.txt"

SERVER_IP="89.116.32.43"

IPSET_V4="ddos_blocklist_v4"
IPSET_GEO="geo_blocklist"

# =========================
# CREATE IPSETS
# =========================
ipset list $IPSET_V4 >/dev/null 2>&1 || ipset create $IPSET_V4 hash:ip timeout $BLOCK_TIME
ipset list $IPSET_GEO >/dev/null 2>&1 || ipset create $IPSET_GEO hash:net

# =========================
# IPTABLES RULES
# =========================
iptables -C INPUT -m set --match-set $IPSET_V4 src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set $IPSET_V4 src -j DROP

iptables -C INPUT -m set --match-set $IPSET_GEO src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set $IPSET_GEO src -j DROP

iptables -C INPUT -s 127.0.0.1 -j ACCEPT 2>/dev/null || iptables -I INPUT -s 127.0.0.1 -j ACCEPT

echo "$(date) - WATCHDOG BULLETPROOF STARTED" >> $LOG

# =========================
# GEO BLOCK LOAD
# =========================
if [ ! -f /tmp/geo_loaded ]; then
    for COUNTRY in cn ru; do
        curl -s https://www.ipdeny.com/ipblocks/data/countries/${COUNTRY}.zone | while read NET; do
            ipset add $IPSET_GEO $NET 2>/dev/null
        done
    done
    touch /tmp/geo_loaded
fi

# =========================
# FUNCTION: STRICT IP EXTRACT
# =========================
get_ips() {
    ss -ntu | awk 'NR>1 {print $5}' \
    | sed 's/\[//g; s/\]//g' \
    | sed 's/^::ffff://' \
    | awk -F: '{print $1}' \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -vE "^(127\.0\.0\.1|$SERVER_IP)$"
}

# =========================
# LOOP
# =========================
while true
do
    DATA=$(get_ips)

    [ -z "$DATA" ] && sleep 10 && continue

    TOP=$(echo "$DATA" | sort | uniq -c | sort -nr | head -n1)

    # SAFE COUNT extraction
    COUNT=$(echo "$TOP" | grep -Eo '^[0-9]+' )

    # BULLETPROOF IP extraction (ONLY real IPv4 allowed)
    IP=$(echo "$TOP" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)

    # =========================
    # HARD DROP INVALID INPUT
    # =========================
    if [[ -z "$IP" || -z "$COUNT" ]]; then
        echo "$(date) - DROPPED INVALID TOP ENTRY: $TOP" >> $LOG
        sleep 5
        continue
    fi

    # =========================
    # WHITELIST
    # =========================
    if [ -f "$WHITELIST_FILE" ] && grep -Fxq "$IP" "$WHITELIST_FILE"; then
        sleep 5
        continue
    fi

    # =========================
    # DB ATTACK DETECTION
    # =========================
    DB_COUNT=$(ss -ntu \
    | awk 'NR>1 {print $5}' \
    | sed 's/\[//g; s/\]//g' \
    | sed 's/^::ffff://' \
    | awk -F: '{print $1}' \
    | grep -F "$IP" \
    | grep -E ':(3306|5432)' | wc -l)

    if [ "$DB_COUNT" -ge "$DB_THRESHOLD" ]; then
        echo "$(date) - DB ATTACK from $IP ($DB_COUNT)" >> $LOG
        echo "DB attack from $IP ($DB_COUNT)" | mail -s "DB ATTACK $HOST" $EMAIL

        ipset add $IPSET_V4 "$IP" timeout 0 2>/dev/null
        echo "$IP" >> $BLACKLIST_FILE

        sleep 10
        continue
    fi

    # =========================
    # HIGH ATTACK
    # =========================
    if [ "$COUNT" -ge "$HIGH_THRESHOLD" ]; then
        echo "$(date) - CRITICAL ATTACK from $IP ($COUNT)" >> $LOG
        echo "CRITICAL DDOS from $IP ($COUNT)" | mail -s "CRITICAL DDOS $HOST" $EMAIL

        ipset add $IPSET_V4 "$IP" timeout 0 2>/dev/null
        echo "$IP" >> $BLACKLIST_FILE

        sleep 10
        continue
    fi

    # =========================
    # NORMAL ATTACK
    # =========================
    if [ "$COUNT" -ge "$CONNECTION_THRESHOLD" ]; then
        echo "$(date) - DDOS detected from $IP ($COUNT)" >> $LOG
        echo "DDOS detected from $IP ($COUNT)" | mail -s "DDOS ALERT $HOST" $EMAIL

        ipset add $IPSET_V4 "$IP" timeout $BLOCK_TIME 2>/dev/null

        sleep 20

        NEW_COUNT=$(echo "$DATA" | grep -F "$IP" | wc -l)

        if [ "$NEW_COUNT" -ge "$CONNECTION_THRESHOLD" ]; then
            echo "$(date) - REPEAT attacker $IP" >> $LOG
            echo "Repeat attacker $IP" | mail -s "REPEAT DDOS $HOST" $EMAIL

            ipset add $IPSET_V4 "$IP" timeout 0 2>/dev/null
            echo "$IP" >> $BLACKLIST_FILE
        fi
    fi

    sleep 15
done
