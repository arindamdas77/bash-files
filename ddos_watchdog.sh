#!/bin/bash

EMAIL="arindam.das@maxbridgesolution.com"
HOST=$(hostname)
CONNECTION_THRESHOLD=200
HIGH_THRESHOLD=400
LOG="/var/log/ddos_watchdog.log"

# Temporary block time
BLOCK_TIME=600

# Files
BLACKLIST_FILE="/var/log/ddos_blacklist.txt"

# ipset
IPSET_NAME="ddos_blocklist"

# Create ipset
ipset list $IPSET_NAME >/dev/null 2>&1 || ipset create $IPSET_NAME hash:ip timeout $BLOCK_TIME

# Ensure iptables rules
iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set $IPSET_NAME src -j DROP

# ✅ Always allow localhost
iptables -C INPUT -s 127.0.0.1 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -s 127.0.0.1 -j ACCEPT

# 🔐 SSH protection (PORT 1807)
iptables -C INPUT -p tcp --dport 1807 -m connlimit --connlimit-above 5 -j DROP 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1807 -m connlimit --connlimit-above 5 -j DROP

# 🔥 HTTP protection
iptables -C INPUT -p tcp --dport 80 -m connlimit --connlimit-above 80 -j DROP 2>/dev/null || \
iptables -I INPUT -p tcp --dport 80 -m connlimit --connlimit-above 80 -j DROP

# 🔥 HTTPS protection
iptables -C INPUT -p tcp --dport 443 -m connlimit --connlimit-above 80 -j DROP 2>/dev/null || \
iptables -I INPUT -p tcp --dport 443 -m connlimit --connlimit-above 80 -j DROP

# 🚫 Drop invalid packets
iptables -C INPUT -m state --state INVALID -j DROP 2>/dev/null || \
iptables -I INPUT -m state --state INVALID -j DROP

while true
do
    # 🚨 Detect & kill malicious python + block attacker IP
    ps aux --sort=-%cpu | awk 'NR>1 && $3>70 {print $2}' | while read PID
    do
        CMD=$(ps -p $PID -o comm=)

        if [[ "$CMD" == "python" || "$CMD" == "python3" ]]; then

            USER=$(ps -p $PID -o user=)

            # Get attacker IP from SSH history
            ATTACK_IP=$(last -i | grep "$USER" | head -n1 | awk '{print $3}')

            echo "$(date) - 🚨 Python attack detected PID $PID by $USER from $ATTACK_IP" >> $LOG

            # Kill process
            kill -9 $PID

            # Block attacker IP permanently
            if [ ! -z "$ATTACK_IP" ] && [ "$ATTACK_IP" != "127.0.0.1" ]; then
                iptables -C INPUT -s $ATTACK_IP -j DROP 2>/dev/null || iptables -A INPUT -s $ATTACK_IP -j DROP
                echo "$ATTACK_IP" >> $BLACKLIST_FILE

                echo "$(date) - Blocked attacker IP $ATTACK_IP (python attack)" >> $LOG
                echo "Blocked IP $ATTACK_IP due to python attack" | mail -s "PYTHON ATTACK $HOST" $EMAIL
            fi
        fi
    done

    # 🔍 DDoS detection
    TOP_IP_INFO=$(ss -ntu | awk 'NR>1 {print $5}' | cut -d: -f1 | grep -v "^$" | sort | uniq -c | sort -nr | head -n1)

    COUNT=$(echo $TOP_IP_INFO | awk '{print $1}')
    IP=$(echo $TOP_IP_INFO | awk '{print $2}')

    [ -z "$IP" ] && sleep 10 && continue

    # 🚨 HIGH ATTACK → PERMANENT BLOCK
    if [ "$COUNT" -ge "$HIGH_THRESHOLD" ]; then
        echo "$(date) - CRITICAL ATTACK from $IP ($COUNT)" >> $LOG
        echo "CRITICAL DDOS from $IP ($COUNT)" | mail -s "CRITICAL DDOS $HOST" $EMAIL

        iptables -C INPUT -s $IP -j DROP 2>/dev/null || iptables -A INPUT -s $IP -j DROP
        echo "$IP" >> $BLACKLIST_FILE

        continue
    fi

    #   NORMAL ATTACK → TEMP BLOCK
    if [ "$COUNT" -ge "$CONNECTION_THRESHOLD" ]; then
        echo "$(date) - DDOS detected from $IP ($COUNT)" >> $LOG
        echo "DDOS detected from $IP ($COUNT)" | mail -s "DDOS ALERT $HOST" $EMAIL

        ipset add $IPSET_NAME $IP timeout $BLOCK_TIME 2>/dev/null

        sleep 20

        NEW_COUNT=$(ss -ntu | awk 'NR>1 {print $5}' | cut -d: -f1 | grep "$IP" | wc -l)

        if [ "$NEW_COUNT" -ge "$CONNECTION_THRESHOLD" ]; then
            echo "$(date) - REPEAT attacker $IP" >> $LOG
            echo "Repeat attacker $IP" | mail -s "REPEAT DDOS $HOST" $EMAIL

            iptables -C INPUT -s $IP -j DROP 2>/dev/null || iptables -A INPUT -s $IP -j DROP
            echo "$IP" >> $BLACKLIST_FILE
        fi
    fi

    sleep 15

done
~
~
