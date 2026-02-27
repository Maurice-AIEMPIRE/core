#!/bin/bash
###############################################################################
# SYSTEM AUDIT ENGINE - Vollstaendige Problemerkennung
# Fuehrt 50+ Checks durch und erstellt einen detaillierten Bericht
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="audit"
REPORT_FILE="$HOME/Desktop/Mac-Audit-$(date +%Y%m%d-%H%M%S).txt"
ISSUES_FILE="$GUARDIAN_DATA/current-issues.json"
ISSUE_COUNT=0
WARN_COUNT=0
CRIT_COUNT=0

# JSON-Array fuer Issues starten
echo '{"audit_date":"'"$(date -Iseconds)"'","issues":[' > "$ISSUES_FILE"
FIRST_ISSUE=true

report() {
    echo -e "$1"
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT_FILE"
}

add_issue() {
    local severity="$1" category="$2" title="$3" details="$4" fix="$5"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    [ "$severity" = "critical" ] && CRIT_COUNT=$((CRIT_COUNT + 1))
    [ "$severity" = "warning" ] && WARN_COUNT=$((WARN_COUNT + 1))

    if [ "$FIRST_ISSUE" = true ]; then
        FIRST_ISSUE=false
    else
        echo ',' >> "$ISSUES_FILE"
    fi

    cat >> "$ISSUES_FILE" << JSONEOF
{"id":$ISSUE_COUNT,"severity":"$severity","category":"$category","title":"$title","details":"$details","fix":"$fix"}
JSONEOF

    local color="$C_YELLOW"
    [ "$severity" = "critical" ] && color="$C_RED"
    [ "$severity" = "info" ] && color="$C_CYAN"
    report "${color}  [$severity] $title${C_NC}"
    report "           $details"
    report "           Fix: $fix"
    report ""
    guardian_log "$MODULE" "$severity" "$category: $title"
}

header() {
    report ""
    report "${C_BLUE}${C_BOLD}╔══════════════════════════════════════════════════╗${C_NC}"
    report "${C_BLUE}${C_BOLD}║  $1$(printf '%*s' $((46 - ${#1})) '')║${C_NC}"
    report "${C_BLUE}${C_BOLD}╚══════════════════════════════════════════════════╝${C_NC}"
}

echo "" > "$REPORT_FILE"
report "${C_BOLD}═══════════════════════════════════════════════════════${C_NC}"
report "${C_BOLD}   MAC SYSTEM AUDIT - Vollstaendige Problemanalyse${C_NC}"
report "${C_BOLD}   $(date)${C_NC}"
report "${C_BOLD}═══════════════════════════════════════════════════════${C_NC}"

###############################################################################
header "A. HARDWARE & SYSTEM-INFO"
###############################################################################
report "  Modell:    $(sysctl -n hw.model 2>/dev/null || echo 'N/A')"
report "  CPU:       $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A')"
report "  Kerne:     $(get_cpu_core_count)"
report "  RAM:       $(get_total_ram_gb) GB"
report "  macOS:     $(get_macos_version)"
report "  Arch:      $(uname -m)"
report "  Uptime:    $(uptime | sed 's/.*up //' | sed 's/,.*//')"
BOOT_TIME=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
if [ -n "$BOOT_TIME" ]; then
    DAYS_UP=$(( ($(date +%s) - BOOT_TIME) / 86400 ))
    if [ "$DAYS_UP" -gt 14 ]; then
        add_issue "warning" "system" "System laeuft seit $DAYS_UP Tagen ohne Neustart" \
            "Lange Uptime kann zu Speicherlecks und instabilem Verhalten fuehren" \
            "Neustart empfohlen (mindestens alle 1-2 Wochen)"
    fi
fi

###############################################################################
header "B. CPU-ANALYSE"
###############################################################################
# Gesamte CPU
CPU_IDLE=$(top -l 2 -n 0 -s 1 2>/dev/null | grep "CPU usage" | tail -1 | awk '{print $7}' | tr -d '%')
if [ -n "$CPU_IDLE" ]; then
    CPU_USED=$((100 - ${CPU_IDLE%.*}))
    report "  Gesamt-CPU: ${CPU_USED}%"
    guardian_record_metric "cpu_total" "$CPU_USED"

    if [ "$CPU_USED" -gt 90 ]; then
        add_issue "critical" "cpu" "CPU-Auslastung bei ${CPU_USED}%" \
            "System ist stark belastet, Eingaben koennen verzoegert sein" \
            "Ressourcen-intensive Apps beenden, Guardian aktivieren"
    elif [ "$CPU_USED" -gt 70 ]; then
        add_issue "warning" "cpu" "CPU-Auslastung erhoht: ${CPU_USED}%" \
            "Merkbare Verlangsamung moeglich" \
            "CPU-intensive Hintergrundprozesse pruefen"
    fi
fi

# Einzelne CPU-Hogs
report "\n  Top CPU-Verbraucher:"
ps aux -r | awk 'NR>1 && NR<=11 {printf "    %-6s %-30s %s%%\n", $2, $11, $3}' | while IFS= read -r line; do
    report "$line"
done

# Runaway-Prozesse (>100% CPU ueber laengere Zeit)
RUNAWAY=$(ps aux -r | awk 'NR>1 && $3>100 {print $2, $11, $3}')
if [ -n "$RUNAWAY" ]; then
    while read -r pid name cpu; do
        add_issue "critical" "cpu" "Runaway-Prozess: $name (${cpu}% CPU)" \
            "PID $pid verbraucht ueber 100% CPU - moeglicherweise haengend oder fehlerhaft" \
            "kill $pid oder App neu starten"
    done <<< "$RUNAWAY"
fi

# kernel_task Check (Thermal Throttling Indikator)
KERNEL_CPU=$(ps aux | grep "kernel_task" | grep -v grep | awk '{print $3}' | head -1)
if [ -n "$KERNEL_CPU" ] && [ "${KERNEL_CPU%.*}" -gt 50 ]; then
    add_issue "critical" "thermal" "kernel_task bei ${KERNEL_CPU}% CPU - Thermal Throttling!" \
        "macOS drosselt den Prozessor wegen Ueberhitzung. kernel_task erzeugt kuenstliche Last." \
        "Mac abkuehlen lassen, Lueftungsschlitze freilegen, Thermal Guardian aktivieren"
fi

###############################################################################
header "C. SPEICHER (RAM) ANALYSE"
###############################################################################
PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
TOTAL_MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
VM=$(vm_stat 2>/dev/null)

if [ -n "$VM" ]; then
    FREE_P=$(echo "$VM" | awk '/Pages free/ {print $3}' | tr -d '.')
    ACTIVE_P=$(echo "$VM" | awk '/Pages active/ {print $3}' | tr -d '.')
    INACTIVE_P=$(echo "$VM" | awk '/Pages inactive/ {print $3}' | tr -d '.')
    WIRED_P=$(echo "$VM" | awk '/Pages wired/ {print $4}' | tr -d '.')
    COMP_P=$(echo "$VM" | awk '/occupied by compressor/ {print $5}' | tr -d '.')
    PAGEINS=$(echo "$VM" | awk '/Pageins/ {print $2}' | tr -d '.')
    PAGEOUTS=$(echo "$VM" | awk '/Pageouts/ {print $2}' | tr -d '.')

    FREE_MB=$(( (FREE_P * PAGE_SIZE) / 1048576 ))
    ACTIVE_MB=$(( (ACTIVE_P * PAGE_SIZE) / 1048576 ))
    WIRED_MB=$(( (WIRED_P * PAGE_SIZE) / 1048576 ))
    COMP_MB=$(( (COMP_P * PAGE_SIZE) / 1048576 ))
    TOTAL_MB=$((TOTAL_MEM / 1048576))
    USED_MB=$((ACTIVE_MB + WIRED_MB + COMP_MB))
    USED_PCT=$((USED_MB * 100 / TOTAL_MB))

    report "  Total:       ${TOTAL_MB} MB"
    report "  Belegt:      ${USED_MB} MB (${USED_PCT}%)"
    report "  Frei:        ${FREE_MB} MB"
    report "  Aktiv:       ${ACTIVE_MB} MB"
    report "  Wired:       ${WIRED_MB} MB"
    report "  Komprimiert: ${COMP_MB} MB"
    report "  Page-ins:    ${PAGEINS}"
    report "  Page-outs:   ${PAGEOUTS}"

    guardian_record_metric "ram_used_pct" "$USED_PCT"

    if [ "$USED_PCT" -gt 92 ]; then
        add_issue "critical" "memory" "RAM fast voll: ${USED_PCT}% belegt" \
            "Nur noch $((TOTAL_MB - USED_MB))MB frei. System swappt vermutlich auf Festplatte." \
            "Memory Guardian aktivieren, RAM-hungrige Apps schliessen"
    elif [ "$USED_PCT" -gt 80 ]; then
        add_issue "warning" "memory" "RAM-Nutzung erhoht: ${USED_PCT}%" \
            "Bei weiterem Anstieg wird das System langsamer" \
            "Nicht benoetigte Apps schliessen, Browser-Tabs reduzieren"
    fi

    # Swap-Analyse
    SWAP_INFO=$(sysctl -n vm.swapusage 2>/dev/null)
    SWAP_USED_MB=$(echo "$SWAP_INFO" | awk '{gsub(/M/,""); print int($6)}')
    SWAP_TOTAL_MB=$(echo "$SWAP_INFO" | awk '{gsub(/M/,""); print int($3)}')
    report "  Swap:        ${SWAP_USED_MB}MB / ${SWAP_TOTAL_MB}MB"

    if [ -n "$SWAP_USED_MB" ] && [ "$SWAP_USED_MB" -gt 4096 ]; then
        add_issue "critical" "memory" "Hohe Swap-Nutzung: ${SWAP_USED_MB}MB" \
            "System lagert Daten auf die langsamere Festplatte aus" \
            "Mehr RAM oder weniger parallele Programme verwenden"
    elif [ -n "$SWAP_USED_MB" ] && [ "$SWAP_USED_MB" -gt 1024 ]; then
        add_issue "warning" "memory" "Swap-Nutzung: ${SWAP_USED_MB}MB" \
            "Leichte Auslagerung auf Festplatte" \
            "RAM-Verbrauch reduzieren"
    fi

    # Memory Pressure
    if [ "$PAGEOUTS" -gt 100000 ]; then
        add_issue "warning" "memory" "Hohe Anzahl Page-outs: $PAGEOUTS" \
            "System musste oft Daten auf Festplatte auslagern" \
            "Deutet auf chronischen RAM-Mangel hin"
    fi

    # Wired Memory pruefen (kann nicht freigegeben werden)
    WIRED_PCT=$((WIRED_MB * 100 / TOTAL_MB))
    if [ "$WIRED_PCT" -gt 40 ]; then
        add_issue "warning" "memory" "Hoher Wired-Memory: ${WIRED_MB}MB (${WIRED_PCT}%)" \
            "Wired Memory kann nicht freigegeben werden" \
            "Kernel-Extensions und Treiber pruefen"
    fi
fi

# Top RAM-Verbraucher
report "\n  Top RAM-Verbraucher:"
ps aux -m | awk 'NR>1 && NR<=11 {printf "    %-6s %-30s %dMB\n", $2, $11, $6/1024}' | while IFS= read -r line; do
    report "$line"
done

# Memory-Leak-Erkennung: Apps mit >2GB RAM
ps aux -m | awk 'NR>1 && $6>2097152 {print $2, $11, int($6/1024)}' | while read -r pid name mem_mb; do
    add_issue "warning" "memory" "$name verbraucht ${mem_mb}MB RAM" \
        "PID $pid - Moeglicherweise ein Speicherleck" \
        "App neu starten um Speicher freizugeben"
done

###############################################################################
header "D. FESTPLATTEN-ANALYSE"
###############################################################################
DISK_RAW=$(df -H / 2>/dev/null | awk 'NR==2')
DISK_TOTAL=$(echo "$DISK_RAW" | awk '{print $2}')
DISK_USED=$(echo "$DISK_RAW" | awk '{print $3}')
DISK_AVAIL=$(echo "$DISK_RAW" | awk '{print $4}')
DISK_PCT=$(echo "$DISK_RAW" | awk '{print $5}' | tr -d '%')

report "  Gesamt:    ${DISK_TOTAL}"
report "  Belegt:    ${DISK_USED} (${DISK_PCT}%)"
report "  Frei:      ${DISK_AVAIL}"

guardian_record_metric "disk_used_pct" "$DISK_PCT"

if [ "$DISK_PCT" -gt 95 ]; then
    add_issue "critical" "disk" "Festplatte fast voll: ${DISK_PCT}% belegt!" \
        "Nur noch ${DISK_AVAIL} frei. macOS braucht mindestens 10-15% freien Platz!" \
        "Sofort Speicher freigeben: Downloads, Papierkorb, alte Apps loeschen"
elif [ "$DISK_PCT" -gt 85 ]; then
    add_issue "warning" "disk" "Festplatte zu ${DISK_PCT}% belegt" \
        "Noch ${DISK_AVAIL} frei - wird langsam eng" \
        "Disk Health Manager aktivieren"
fi

# Groesste Ordner
report "\n  Groesste Ordner:"
du -sh ~/Downloads ~/Library/Caches ~/Library/Application\ Support \
    ~/Library/Developer ~/Library/Containers ~/.Trash \
    ~/Documents ~/Desktop ~/Movies ~/Music ~/Pictures \
    2>/dev/null | sort -rh | head -10 | while IFS= read -r line; do
    report "    $line"
done

# Cache-Groesse
CACHE_SIZE=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}')
report "\n  Cache-Groesse: ${CACHE_SIZE}"

CACHE_BYTES=$(du -sk ~/Library/Caches 2>/dev/null | awk '{print $1}')
if [ -n "$CACHE_BYTES" ] && [ "$CACHE_BYTES" -gt 10485760 ]; then
    add_issue "warning" "disk" "Cache-Ordner ueber 10GB: ${CACHE_SIZE}" \
        "Alte Caches verbrauchen viel Platz" \
        "Disk Manager wird Caches automatisch bereinigen"
fi

# Papierkorb
TRASH_SIZE=$(du -sh ~/.Trash 2>/dev/null | awk '{print $1}')
TRASH_KB=$(du -sk ~/.Trash 2>/dev/null | awk '{print $1}')
if [ -n "$TRASH_KB" ] && [ "$TRASH_KB" -gt 1048576 ]; then
    add_issue "warning" "disk" "Papierkorb: ${TRASH_SIZE}" \
        "Vergessene Dateien im Papierkorb belegen Platz" \
        "Papierkorb leeren"
fi

# Downloads pruefen
DL_SIZE=$(du -sh ~/Downloads 2>/dev/null | awk '{print $1}')
DL_KB=$(du -sk ~/Downloads 2>/dev/null | awk '{print $1}')
if [ -n "$DL_KB" ] && [ "$DL_KB" -gt 5242880 ]; then
    add_issue "info" "disk" "Downloads-Ordner: ${DL_SIZE}" \
        "Alte Downloads koennten aufgeraeumt werden" \
        "Downloads pruefen und alte Dateien loeschen"
fi

# SMART-Status (SSD-Gesundheit)
SMART=$(diskutil info disk0 2>/dev/null | grep "SMART Status" | awk -F: '{print $2}' | xargs)
report "\n  SSD SMART-Status: ${SMART:-N/A}"
if [ -n "$SMART" ] && [ "$SMART" != "Verified" ]; then
    add_issue "critical" "disk" "SSD SMART-Status: $SMART" \
        "Die Festplatte hat moeglicherweise Probleme!" \
        "SOFORT Backup machen! SSD koennte ausfallen."
fi

###############################################################################
header "E. THERMISCHE ANALYSE"
###############################################################################
# SMC-Daten (Temperatur, Luefter)
report "  Thermische Daten:"

# Versuche powermetrics (braucht sudo)
THERMAL_DATA=$(sudo powermetrics --samplers smc -i 1 -n 1 2>/dev/null | head -20)
if [ -n "$THERMAL_DATA" ]; then
    CPU_TEMP=$(echo "$THERMAL_DATA" | grep "CPU die temperature" | awk '{print $4}')
    GPU_TEMP=$(echo "$THERMAL_DATA" | grep "GPU die temperature" | awk '{print $4}')
    report "  CPU-Temperatur: ${CPU_TEMP:-N/A}°C"
    report "  GPU-Temperatur: ${GPU_TEMP:-N/A}°C"

    if [ -n "$CPU_TEMP" ]; then
        TEMP_INT=${CPU_TEMP%.*}
        guardian_record_metric "cpu_temp" "$TEMP_INT"
        if [ "$TEMP_INT" -gt 95 ]; then
            add_issue "critical" "thermal" "CPU-Temperatur KRITISCH: ${CPU_TEMP}°C" \
                "CPU wird thermisch gedrosselt! Leistung reduziert!" \
                "Mac kuehlen, Lueftungsschlitze freilegen, Thermal Guardian aktivieren"
        elif [ "$TEMP_INT" -gt 80 ]; then
            add_issue "warning" "thermal" "CPU-Temperatur hoch: ${CPU_TEMP}°C" \
                "Nahe an der Drosselungsgrenze" \
                "CPU-Last reduzieren oder bessere Kuehlung"
        fi
    fi
else
    report "  (sudo-Rechte fuer Temperatur-Daten benoetigt)"
fi

# Luefter-Status
FAN_DATA=$(sudo powermetrics --samplers smc -i 1 -n 1 2>/dev/null | grep -i "fan")
if [ -n "$FAN_DATA" ]; then
    report "  Luefter: $FAN_DATA"
fi

# pmset thermal
PMSET_THERMAL=$(pmset -g thermlog 2>/dev/null | tail -3)
if echo "$PMSET_THERMAL" | grep -qi "speed_limit.*[0-9]"; then
    SPEED_LIMIT=$(echo "$PMSET_THERMAL" | grep -i "speed_limit" | awk '{print $NF}')
    if [ -n "$SPEED_LIMIT" ] && [ "$SPEED_LIMIT" -lt 100 ]; then
        add_issue "critical" "thermal" "CPU wird auf ${SPEED_LIMIT}% gedrosselt" \
            "Thermal Throttling aktiv - Mac ist zu heiss!" \
            "Thermal Guardian installieren"
    fi
fi

###############################################################################
header "F. NETZWERK-ANALYSE"
###############################################################################
# Interface
ACTIVE_IF=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
report "  Aktives Interface: ${ACTIVE_IF:-N/A}"

# Wi-Fi Details
if [ -n "$ACTIVE_IF" ]; then
    WIFI_INFO=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null)
    if [ -n "$WIFI_INFO" ]; then
        SSID=$(echo "$WIFI_INFO" | awk '/ SSID/ {print $2}')
        RSSI=$(echo "$WIFI_INFO" | awk '/agrCtlRSSI/ {print $2}')
        NOISE=$(echo "$WIFI_INFO" | awk '/agrCtlNoise/ {print $2}')
        TX_RATE=$(echo "$WIFI_INFO" | awk '/lastTxRate/ {print $2}')
        CHANNEL=$(echo "$WIFI_INFO" | awk '/channel/ {print $2}')
        report "  Wi-Fi SSID:    $SSID"
        report "  Signal (RSSI): $RSSI dBm"
        report "  Noise:         $NOISE dBm"
        report "  TX Rate:       ${TX_RATE}Mbps"
        report "  Kanal:         $CHANNEL"

        if [ -n "$RSSI" ] && [ "$RSSI" -lt -70 ]; then
            add_issue "warning" "network" "Schwaches Wi-Fi Signal: $RSSI dBm" \
                "Verbindung ist instabil, Geschwindigkeit reduziert" \
                "Naeher zum Router, Repeater verwenden, oder Ethernet-Kabel nutzen"
        fi

        # SNR (Signal-to-Noise Ratio)
        if [ -n "$RSSI" ] && [ -n "$NOISE" ]; then
            SNR=$((RSSI - NOISE))
            if [ "$SNR" -lt 20 ]; then
                add_issue "warning" "network" "Schlechtes Signal-Rausch-Verhaeltnis: $SNR dB" \
                    "Viel WLAN-Interferenz in der Umgebung" \
                    "WLAN-Kanal wechseln, 5GHz Band nutzen"
            fi
        fi
    fi
fi

# DNS-Geschwindigkeit
DNS_TIME=$(dig google.com +time=5 +tries=1 2>/dev/null | grep "Query time" | awk '{print $4}')
if [ -n "$DNS_TIME" ]; then
    report "  DNS-Aufloesung: ${DNS_TIME}ms"
    guardian_record_metric "dns_latency" "$DNS_TIME"
    if [ "$DNS_TIME" -gt 200 ]; then
        add_issue "warning" "network" "DNS langsam: ${DNS_TIME}ms" \
            "Webseiten laden langsam wegen DNS" \
            "DNS-Server wechseln (1.1.1.1 oder 8.8.8.8)"
    fi
fi

# Ping-Latenz
PING_OUT=$(ping -c 5 -W 3 8.8.8.8 2>/dev/null)
if [ -n "$PING_OUT" ]; then
    PING_AVG=$(echo "$PING_OUT" | tail -1 | awk -F'/' '{print $5}')
    PACKET_LOSS=$(echo "$PING_OUT" | grep "packet loss" | awk '{print $7}')
    report "  Ping (8.8.8.8): ${PING_AVG}ms"
    report "  Paketverlust:   $PACKET_LOSS"

    PING_INT=${PING_AVG%.*}
    if [ -n "$PING_INT" ] && [ "$PING_INT" -gt 100 ]; then
        add_issue "warning" "network" "Hohe Latenz: ${PING_AVG}ms" \
            "Verzoegerungen bei allen Internet-Aktivitaeten" \
            "Netzwerk pruefen, ISP kontaktieren"
    fi

    if [ "$PACKET_LOSS" != "0.0%" ] && [ "$PACKET_LOSS" != "0%" ]; then
        add_issue "warning" "network" "Paketverlust: $PACKET_LOSS" \
            "Verbindung ist instabil" \
            "WLAN-Verbindung oder Kabel pruefen"
    fi
else
    add_issue "critical" "network" "Keine Internet-Verbindung" \
        "Ping zu 8.8.8.8 fehlgeschlagen" \
        "Netzwerkverbindung pruefen"
fi

# Offene Verbindungen
CONN_COUNT=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
CONN_WAIT=$(netstat -an 2>/dev/null | grep -c TIME_WAIT)
report "  Aktive Verbindungen: $CONN_COUNT"
report "  TIME_WAIT:           $CONN_WAIT"

if [ "$CONN_COUNT" -gt 300 ]; then
    add_issue "warning" "network" "Sehr viele offene Verbindungen: $CONN_COUNT" \
        "Koennte auf Malware oder fehlerhafte App hindeuten" \
        "Netzwerk-Verbindungen pruefen mit: lsof -i -P"
fi

###############################################################################
header "G. AUTOSTART & HINTERGRUND-PROZESSE"
###############################################################################
# Login Items
report "  Login-Items:"
LOGIN_ITEMS=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)
echo "$LOGIN_ITEMS" | tr ',' '\n' | while IFS= read -r item; do
    item=$(echo "$item" | xargs)
    [ -z "$item" ] && continue
    report "    - $item"
done

LOGIN_COUNT=$(echo "$LOGIN_ITEMS" | tr ',' '\n' | grep -c '[a-zA-Z]')
if [ "$LOGIN_COUNT" -gt 8 ]; then
    add_issue "warning" "startup" "${LOGIN_COUNT} Login-Items" \
        "Viele Programme starten beim Login und verlangsamen den Systemstart" \
        "Nicht benoetigte Login-Items entfernen"
fi

# LaunchAgents
report "\n  Benutzer-LaunchAgents:"
USER_AGENTS=$(ls ~/Library/LaunchAgents/ 2>/dev/null | grep -v mac-guardian)
AGENT_COUNT=0
while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    AGENT_COUNT=$((AGENT_COUNT + 1))
    report "    - $agent"
done <<< "$USER_AGENTS"

if [ "$AGENT_COUNT" -gt 15 ]; then
    add_issue "warning" "startup" "${AGENT_COUNT} LaunchAgents im Benutzerordner" \
        "Viele Hintergrundprozesse belasten das System dauerhaft" \
        "Nicht benoetigte LaunchAgents deaktivieren"
fi

# Gesamtanzahl Prozesse
TOTAL_PROCS=$(ps aux | wc -l | tr -d ' ')
report "\n  Laufende Prozesse: $TOTAL_PROCS"
if [ "$TOTAL_PROCS" -gt 400 ]; then
    add_issue "warning" "processes" "Viele laufende Prozesse: $TOTAL_PROCS" \
        "Jeder Prozess verbraucht Ressourcen" \
        "Nicht benoetigte Apps und Dienste beenden"
fi

###############################################################################
header "H. BROWSER-ANALYSE"
###############################################################################
for browser in "Google Chrome" "Safari" "Firefox" "Microsoft Edge" "Arc" "Brave Browser"; do
    PIDS=$(pgrep -f "$browser" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        PROC_COUNT=$(echo "$PIDS" | wc -l | tr -d ' ')
        TOTAL_MEM=$(ps -p $(echo "$PIDS" | tr '\n' ',') -o rss= 2>/dev/null | awk '{sum+=$1} END {print int(sum/1024)}')
        TOTAL_CPU=$(ps -p $(echo "$PIDS" | tr '\n' ',') -o %cpu= 2>/dev/null | awk '{sum+=$1} END {print int(sum)}')

        report "  ${browser}:"
        report "    Prozesse: $PROC_COUNT"
        report "    RAM:      ${TOTAL_MEM}MB"
        report "    CPU:      ${TOTAL_CPU}%"

        if [ "$TOTAL_MEM" -gt 4096 ]; then
            add_issue "warning" "browser" "$browser verbraucht ${TOTAL_MEM}MB RAM" \
                "$PROC_COUNT Prozesse (ca. Tabs) laufen" \
                "Tabs schliessen! Unter 20 Tabs halten fuer stabile Performance"
        fi

        if [ "$TOTAL_CPU" -gt 50 ]; then
            add_issue "warning" "browser" "$browser verbraucht ${TOTAL_CPU}% CPU" \
                "Schwere Webseiten oder Extensions belasten die CPU" \
                "Schwere Tabs schliessen, Extensions pruefen"
        fi

        # Chrome-spezifisch: Helper-Prozesse
        if [[ "$browser" == "Google Chrome" ]]; then
            HELPER_COUNT=$(pgrep -f "Chrome Helper" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$HELPER_COUNT" -gt 50 ]; then
                add_issue "warning" "browser" "Chrome: $HELPER_COUNT Helper-Prozesse" \
                    "Jeder Tab und jede Extension erzeugt einen eigenen Prozess" \
                    "Chrome Tab-Management oder OneTab Extension verwenden"
            fi
        fi
    fi
done

###############################################################################
header "I. SPOTLIGHT & INDEXIERUNG"
###############################################################################
MDS_CPU=$(ps aux | grep "mds_stores" | grep -v grep | awk '{print $3}' | head -1)
MDS_MEM=$(ps aux | grep "mds_stores" | grep -v grep | awk '{print $6}' | head -1)
report "  mds_stores CPU: ${MDS_CPU:-0}%"
report "  mds_stores RAM: $(( ${MDS_MEM:-0} / 1024 ))MB"

if [ -n "$MDS_CPU" ] && [ "${MDS_CPU%.*}" -gt 20 ]; then
    add_issue "warning" "spotlight" "Spotlight-Indexierung verbraucht ${MDS_CPU}% CPU" \
        "Spotlight indexiert Dateien im Hintergrund" \
        "Spotlight-Index neu aufbauen oder Ordner ausschliessen"
fi

# Spotlight-Ordner mit .metadata_never_index pruefen
INDEXABLE_NODE_MODULES=$(find ~ -maxdepth 4 -name "node_modules" -type d ! -exec test -f "{}/.metadata_never_index" \; -print 2>/dev/null | wc -l | tr -d ' ')
if [ "$INDEXABLE_NODE_MODULES" -gt 0 ]; then
    add_issue "info" "spotlight" "$INDEXABLE_NODE_MODULES node_modules Ordner werden von Spotlight indexiert" \
        "Entwickler-Ordner sollten nicht indexiert werden" \
        "03-dauerhafte-optimierung.sh fuehrt dies automatisch durch"
fi

###############################################################################
header "J. ENERGIE & BATTERIE"
###############################################################################
POWER_SOURCE=$(pmset -g ps 2>/dev/null | head -1 | grep -o "'.*'" | tr -d "'")
report "  Stromquelle: ${POWER_SOURCE:-N/A}"

BATTERY_INFO=$(pmset -g batt 2>/dev/null)
BATTERY_PCT=$(echo "$BATTERY_INFO" | grep -o '[0-9]*%' | head -1 | tr -d '%')
BATTERY_STATE=$(echo "$BATTERY_INFO" | grep -o 'charging\|discharging\|charged\|AC attached' | head -1)
BATTERY_HEALTH=$(system_profiler SPPowerDataType 2>/dev/null | grep "Condition" | awk -F: '{print $2}' | xargs)
CYCLE_COUNT=$(system_profiler SPPowerDataType 2>/dev/null | grep "Cycle Count" | awk -F: '{print $2}' | xargs)

report "  Batterie:     ${BATTERY_PCT:-N/A}%"
report "  Status:       ${BATTERY_STATE:-N/A}"
report "  Zustand:      ${BATTERY_HEALTH:-N/A}"
report "  Ladezyklen:   ${CYCLE_COUNT:-N/A}"

if [ -n "$BATTERY_HEALTH" ] && [ "$BATTERY_HEALTH" != "Normal" ]; then
    add_issue "warning" "battery" "Batterie-Zustand: $BATTERY_HEALTH" \
        "Batterie zeigt Verschleiss nach $CYCLE_COUNT Zyklen" \
        "Batterie-Austausch in Betracht ziehen"
fi

if [ -n "$CYCLE_COUNT" ] && [ "$CYCLE_COUNT" -gt 800 ]; then
    add_issue "info" "battery" "Hohe Zyklenzahl: $CYCLE_COUNT" \
        "Standard-Lebensdauer ist ca. 1000 Zyklen" \
        "Batterie-Gesundheit im Auge behalten"
fi

# Energy-intensive Prozesse
report "\n  Energieverbrauch-Ranking:"
top -l 1 -n 10 -s 0 -stats pid,command,power 2>/dev/null | tail -10 | while IFS= read -r line; do
    report "    $line"
done

###############################################################################
header "K. SICHERHEITS-CHECK"
###############################################################################
# SIP Status
SIP_STATUS=$(csrutil status 2>/dev/null | awk -F: '{print $2}' | xargs)
report "  SIP:          ${SIP_STATUS:-N/A}"
if [ -n "$SIP_STATUS" ] && echo "$SIP_STATUS" | grep -qi "disabled"; then
    add_issue "critical" "security" "System Integrity Protection (SIP) deaktiviert!" \
        "SIP schuetzt vor Malware und System-Manipulation" \
        "SIP im Recovery Mode wieder aktivieren: csrutil enable"
fi

# Firewall
FIREWALL=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
report "  Firewall:     $([ "$FIREWALL" = "1" ] && echo "aktiv" || echo "INAKTIV")"
if [ "$FIREWALL" != "1" ]; then
    add_issue "warning" "security" "Firewall ist deaktiviert" \
        "System ist nicht vor eingehenden Verbindungen geschuetzt" \
        "Firewall aktivieren in Systemeinstellungen > Sicherheit"
fi

# FileVault
FV_STATUS=$(fdesetup status 2>/dev/null)
report "  FileVault:    $FV_STATUS"
if echo "$FV_STATUS" | grep -qi "off"; then
    add_issue "info" "security" "FileVault (Festplattenverschluesselung) ist aus" \
        "Daten auf der Festplatte sind nicht verschluesselt" \
        "FileVault aktivieren fuer besseren Datenschutz"
fi

# Gatekeeper
GK_STATUS=$(spctl --status 2>/dev/null)
report "  Gatekeeper:   $GK_STATUS"

###############################################################################
header "L. macOS UPDATES"
###############################################################################
# Verfuegbare Updates
UPDATES=$(softwareupdate -l 2>/dev/null | grep -c "Label:")
report "  Verfuegbare Updates: $UPDATES"
if [ "$UPDATES" -gt 0 ]; then
    add_issue "info" "updates" "$UPDATES macOS-Updates verfuegbar" \
        "Updates enthalten Sicherheits- und Performance-Fixes" \
        "Updates installieren: Systemeinstellungen > Software-Update"

    softwareupdate -l 2>/dev/null | grep "Label:" | while IFS= read -r line; do
        report "    $line"
    done
fi

###############################################################################
# ABSCHLUSS-ZUSAMMENFASSUNG
###############################################################################
echo ']}' >> "$ISSUES_FILE"

header "AUDIT ZUSAMMENFASSUNG"
report ""
report "  ${C_RED}${C_BOLD}Kritische Probleme:  $CRIT_COUNT${C_NC}"
report "  ${C_YELLOW}${C_BOLD}Warnungen:           $WARN_COUNT${C_NC}"
report "  ${C_BOLD}Gesamt-Issues:       $ISSUE_COUNT${C_NC}"
report ""

if [ "$CRIT_COUNT" -gt 0 ]; then
    report "  ${C_RED}${C_BOLD}⚠  KRITISCHE PROBLEME GEFUNDEN!${C_NC}"
    report "  ${C_RED}  Sofortige Massnahmen erforderlich.${C_NC}"
elif [ "$WARN_COUNT" -gt 0 ]; then
    report "  ${C_YELLOW}${C_BOLD}  Warnungen gefunden - Optimierung empfohlen.${C_NC}"
else
    report "  ${C_GREEN}${C_BOLD}  System ist in gutem Zustand!${C_NC}"
fi

report ""
report "  Report gespeichert: $REPORT_FILE"
report "  Issues-Datei:       $ISSUES_FILE"
report ""

guardian_log "$MODULE" "INFO" "Audit abgeschlossen: $CRIT_COUNT kritisch, $WARN_COUNT Warnungen, $ISSUE_COUNT gesamt"
guardian_notify "Audit abgeschlossen" "$CRIT_COUNT kritische, $WARN_COUNT Warnungen gefunden" \
    "$([ "$CRIT_COUNT" -gt 0 ] && echo 'critical' || echo 'normal')"
