#!/bin/bash
###############################################################################
# NETWORK OPTIMIZER - DNS, Latenz, Bandbreite
#
# - Automatische DNS-Optimierung (schnellsten DNS waehlen)
# - Wi-Fi Signal-Monitoring
# - Bandbreiten-Ueberwachung
# - Automatischer DNS-Cache-Flush bei Problemen
# - Erkennung von Netzwerk-Ausfaellen
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="network"
NET_DATA="$GUARDIAN_DATA/network"
mkdir -p "$NET_DATA"

# DNS-Server zum Testen
DNS_SERVERS=(
    "1.1.1.1|Cloudflare"
    "8.8.8.8|Google"
    "9.9.9.9|Quad9"
    "208.67.222.222|OpenDNS"
)

###############################################################################
# DNS-OPTIMIERUNG
###############################################################################

# Teste DNS-Server-Geschwindigkeit
test_dns_speed() {
    local server="$1"
    local time
    time=$(dig @"$server" google.com +time=3 +tries=1 2>/dev/null | \
        grep "Query time" | awk '{print $4}')
    echo "${time:-9999}"
}

# Finde schnellsten DNS-Server
find_fastest_dns() {
    local best_server="" best_time=9999 best_name=""

    for entry in "${DNS_SERVERS[@]}"; do
        IFS='|' read -r server name <<< "$entry"
        local time
        time=$(test_dns_speed "$server")
        guardian_log "$MODULE" "DNS_TEST" "$name ($server): ${time}ms"

        if [ "$time" -lt "$best_time" ]; then
            best_time=$time
            best_server=$server
            best_name=$name
        fi
    done

    echo "$best_server|$best_name|$best_time"
}

# DNS-Server setzen
set_dns_server() {
    local server="$1" name="$2"
    local interface
    interface=$(route get default 2>/dev/null | grep interface | awk '{print $2}')

    if [ -n "$interface" ]; then
        local service
        service=$(networksetup -listallhardwareports 2>/dev/null | \
            grep -B1 "$interface" | grep "Hardware Port" | awk -F: '{print $2}' | xargs)

        if [ -n "$service" ]; then
            sudo networksetup -setdnsservers "$service" "$server" 2>/dev/null
            guardian_log "$MODULE" "DNS_SET" "DNS geaendert zu $name ($server) auf $service"
            guardian_notify "DNS optimiert" "Verwende jetzt $name ($server)" "success"

            # DNS-Cache leeren
            sudo dscacheutil -flushcache 2>/dev/null
            sudo killall -HUP mDNSResponder 2>/dev/null
        fi
    fi
}

# Automatische DNS-Optimierung
optimize_dns() {
    # Aktuellen DNS testen
    local current_dns_time
    current_dns_time=$(dig google.com +time=3 +tries=1 2>/dev/null | \
        grep "Query time" | awk '{print $4}')
    current_dns_time=${current_dns_time:-9999}

    guardian_log "$MODULE" "DNS" "Aktueller DNS: ${current_dns_time}ms"

    # Wenn aktueller DNS langsam ist (>150ms), optimieren
    if [ "$current_dns_time" -gt 150 ]; then
        local result
        result=$(find_fastest_dns)
        IFS='|' read -r best_server best_name best_time <<< "$result"

        if [ "$best_time" -lt "$current_dns_time" ]; then
            guardian_log "$MODULE" "DNS_OPTIMIZE" "Wechsle DNS: ${current_dns_time}ms -> ${best_name} ${best_time}ms"
            set_dns_server "$best_server" "$best_name"
        fi
    fi
}

###############################################################################
# WI-FI MONITORING
###############################################################################

get_wifi_info() {
    local wifi
    wifi=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null)
    [ -z "$wifi" ] && echo "disconnected" && return

    local rssi noise tx_rate
    rssi=$(echo "$wifi" | awk '/agrCtlRSSI/ {print $2}')
    noise=$(echo "$wifi" | awk '/agrCtlNoise/ {print $2}')
    tx_rate=$(echo "$wifi" | awk '/lastTxRate/ {print $2}')

    echo "${rssi}|${noise}|${tx_rate}"
}

check_wifi() {
    local info
    info=$(get_wifi_info)

    if [ "$info" = "disconnected" ]; then
        guardian_log "$MODULE" "WARN" "Wi-Fi getrennt"
        return
    fi

    IFS='|' read -r rssi noise tx_rate <<< "$info"
    guardian_record_metric "wifi_rssi" "${rssi#-}"
    guardian_record_metric "wifi_txrate" "$tx_rate"

    # Signal-Qualitaet bewerten
    if [ "$rssi" -lt -80 ]; then
        guardian_log "$MODULE" "WARN" "Sehr schwaches Wi-Fi: ${rssi}dBm"
        guardian_notify "Wi-Fi schwach" "Signal: ${rssi}dBm - Verbindung instabil" "critical"
    elif [ "$rssi" -lt -70 ]; then
        guardian_log "$MODULE" "INFO" "Schwaches Wi-Fi: ${rssi}dBm"
    fi
}

###############################################################################
# KONNEKTIVITAETS-CHECK
###############################################################################

check_connectivity() {
    # Schneller Check: Ping
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        guardian_log "$MODULE" "ALERT" "Internet nicht erreichbar!"
        guardian_notify "Kein Internet!" "Verbindung unterbrochen" "critical"
        guardian_record_event "network_down" "ping_failed" "notify"

        # DNS-Cache leeren als erste Massnahme
        sudo dscacheutil -flushcache 2>/dev/null
        sudo killall -HUP mDNSResponder 2>/dev/null

        echo "down"
        return
    fi

    # Latenz messen
    local ping_avg
    ping_avg=$(ping -c 3 -W 3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    if [ -n "$ping_avg" ]; then
        guardian_record_metric "ping_latency" "${ping_avg%.*}"
    fi

    # DNS-Latenz
    local dns_time
    dns_time=$(dig google.com +time=3 +tries=1 2>/dev/null | \
        grep "Query time" | awk '{print $4}')
    if [ -n "$dns_time" ]; then
        guardian_record_metric "dns_latency" "$dns_time"

        if [ "$dns_time" -gt 300 ]; then
            guardian_log "$MODULE" "WARN" "DNS extrem langsam: ${dns_time}ms - optimiere"
            optimize_dns
        fi
    fi

    echo "up|${ping_avg:-0}|${dns_time:-0}"
}

###############################################################################
# NETZWERK-TUNING
###############################################################################

tune_network() {
    guardian_log "$MODULE" "TUNE" "Netzwerk-Parameter optimieren"

    # TCP Window Scaling
    sudo sysctl -w net.inet.tcp.win_scale_factor=8 2>/dev/null || true

    # Receive/Send Buffer
    sudo sysctl -w net.inet.tcp.recvspace=524288 2>/dev/null || true
    sudo sysctl -w net.inet.tcp.sendspace=524288 2>/dev/null || true

    # Schnellere TCP-Verbindungen
    sudo sysctl -w net.inet.tcp.delayed_ack=0 2>/dev/null || true

    # Mehr offene Dateien erlauben
    sudo sysctl -w kern.maxfiles=65536 2>/dev/null || true
    sudo sysctl -w kern.maxfilesperproc=65536 2>/dev/null || true

    guardian_log "$MODULE" "TUNE" "Netzwerk-Parameter optimiert"
}

###############################################################################
# HAUPT-CHECK
###############################################################################

network_check() {
    local conn
    conn=$(check_connectivity)

    # Wi-Fi pruefen (alle 6 Checks = 1 Minute)
    local check_file="$NET_DATA/check_count"
    local count
    count=$(cat "$check_file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$check_file"

    if [ $((count % 6)) -eq 0 ]; then
        check_wifi
    fi

    # DNS-Optimierung (alle 360 Checks = 1 Stunde)
    if [ $((count % 360)) -eq 0 ]; then
        optimize_dns
    fi

    echo "$conn"
}

# Direkter Aufruf
case "${1:-check}" in
    check)      network_check ;;
    dns)        optimize_dns ;;
    wifi)       get_wifi_info ;;
    tune)       tune_network ;;
    status)
        echo "Connectivity: $(check_connectivity)"
        echo "Wi-Fi: $(get_wifi_info)"
        ;;
    *)          echo "Network Optimizer: $0 {check|dns|wifi|tune|status}" ;;
esac
