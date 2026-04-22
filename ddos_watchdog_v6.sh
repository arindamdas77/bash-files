#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)

CONNECTION_THRESHOLD=200
HIGH_THRESHOLD=400
BLOCK_TIME=600

LOG="/var/log/ddos_watchdog.log"
BLACKLIST_FILE="/var/log/ddos_blacklist.txt"

# ipset names
IPSET_V4="ddos_blocklist_v4"
IPSET_V6="ddos_blocklist_v6"

# =========================
# CREATE IPSETS
# =========================
ipset list $IPSET_V4 >/dev/null 2>&1 || ipset create $IPSET_V4 hash:ip timeout $BLOCK_TIME
ipset list $IPSET_V6 >/dev/null 2>&1 || ipset create $IPSET_V6 hash:ip family inet6 timeout $BLOCK_TIME

# =========================
# IPTABLES RULES
# =========================
iptables -C INPUT -m set --match-set $IPSET_V4 src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set $IPSET_V4 src -j DROP

ip6tables -C INPUT -m set --match-set $IPSET_V6 src -j DROP 2>/dev/null || \
ip6tables -I INPUT -m set --match-set $IPSET_V6 src -j DROP

# Allow localhost
iptables -C INPUT -s 127.0.0.1 -j ACCEPT 2>/dev/null || iptables -I INPUT -s 127.0.0.1 -j ACCEPT
ip6tables -C INPUT -s ::1 -j ACCEPT 2>/dev/null || ip6tables -I INPUT -s ::1 -j ACCEPT

echo "$(date) - DDOS IPv4+IPv6 protection started" >> $LOG

# =========================
# LOOP
# =========================
while true
do
    # 🔍 GET IPs (SAFE PARSE)
    TOP_IP_INFO=$(ss -ntu \
    | awk 'NR>1 {print $5}' \
    | sed 's/\[//g' | sed 's/\]//g' \
    | awk -F: '{print $(NF-1)}' \
    | grep -v "^$" \
    | sort | uniq -c | sort -nr | head -n1)

    COUNT=$(echo "$TOP_IP_INFO" | awk '{print $1}')
    IP=$(echo "$TOP_IP_INFO" | awk '{print $2}')

    [ -z "$IP" ] && sleep 10 && continue

    # =========================
    # DETECT IP VERSION
    # =========================
    if [[ "$IP" =~ : ]]; then
        IP_VERSION="v6"
    else
        IP_VERSION="v4"
    fi

    # =========================
    # HIGH ATTACK
    # =========================
    if [ "$COUNT" -ge "$HIGH_THRESHOLD" ]; then

        echo "$(date) - CRITICAL ATTACK from $IP ($COUNT)" >> $LOG
        echo "CRITICAL DDOS from $IP ($COUNT)" | mail -s "CRITICAL DDOS $HOST" $EMAIL

        if [ "$IP_VERSION" == "v6" ]; then
            ipset add $IPSET_V6 $IP timeout 0 2>/dev/null
        else
            ipset add $IPSET_V4 $IP timeout 0 2>/dev/null
        fi

        echo "$IP" >> $BLACKLIST_FILE
        continue
    fi

    # =========================
    # NORMAL ATTACK
    # =========================
    if [ "$COUNT" -ge "$CONNECTION_THRESHOLD" ]; then

        echo "$(date) - DDOS detected from $IP ($COUNT)" >> $LOG
        echo "DDOS detected from $IP ($COUNT)" | mail -s "DDOS ALERT $HOST" $EMAIL

        if [ "$IP_VERSION" == "v6" ]; then
            ipset add $IPSET_V6 $IP timeout $BLOCK_TIME 2>/dev/null
        else
            ipset add $IPSET_V4 $IP timeout $BLOCK_TIME 2>/dev/null
        fi

        sleep 20

        NEW_COUNT=$(ss -ntu \
        | awk 'NR>1 {print $5}' \
        | sed 's/\[//g' | sed 's/\]//g' \
        | awk -F: '{print $(NF-1)}' \
        | grep "$IP" | wc -l)

        if [ "$NEW_COUNT" -ge "$CONNECTION_THRESHOLD" ]; then

            echo "$(date) - REPEAT attacker $IP" >> $LOG
            echo "Repeat attacker $IP" | mail -s "REPEAT DDOS $HOST" $EMAIL

            if [ "$IP_VERSION" == "v6" ]; then
                ipset add $IPSET_V6 $IP timeout 0 2>/dev/null
            else
                ipset add $IPSET_V4 $IP timeout 0 2>/dev/null
            fi

            echo "$IP" >> $BLACKLIST_FILE
        fi
    fi

    sleep 15
done
