#!/usr/bin/env bash
# ============================================================================
# Smart Monitor - Proaktive Problemerkennung mit Mustererkennung
# Erkennt Probleme BEVOR sie entstehen durch historische Analyse
# ============================================================================
set -euo pipefail

GUARDIAN_DIR="$HOME/.mac-guardian"
LOG_DIR="$GUARDIAN_DIR/logs"
LEARNING_DB="$GUARDIAN_DIR/learning.json"
PREDICTIONS_FILE="$GUARDIAN_DIR/predictions.json"
METRICS_HISTORY="$GUARDIAN_DIR/metrics-history.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Metrics Collection & History
# ============================================================================
collect_metrics() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hour
    hour=$(date '+%H')
    local day_of_week
    day_of_week=$(date '+%u')

    # CPU
    local cpu
    if [[ "$(uname)" == "Darwin" ]]; then
        cpu=$(top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ {print 100 - $7}' | tr -d '%')
    else
        cpu=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f", usage}')
    fi

    # Memory
    local mem
    if [[ "$(uname)" == "Darwin" ]]; then
        local mem_info page_size pages_active pages_wired total_mem
        mem_info=$(vm_stat 2>/dev/null)
        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        pages_active=$(echo "$mem_info" | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
        pages_wired=$(echo "$mem_info" | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')
        total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        local used_mem=$(( (pages_active + pages_wired) * page_size ))
        mem=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc 2>/dev/null || echo "0")
    else
        mem=$(free 2>/dev/null | awk '/Mem:/ {printf("%.1f", $3/$2 * 100)}')
    fi

    # Disk
    local disk
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

    # Process count
    local proc_count
    proc_count=$(ps aux 2>/dev/null | wc -l | tr -d ' ')

    # Network connections
    local net_conns
    net_conns=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo "0")

    # Top CPU process
    local top_proc
    top_proc=$(ps aux 2>/dev/null | sort -nrk 3 | awk 'NR==2 {print $11}' | head -1)

    # Store metric
    if command -v jq &>/dev/null; then
        if [[ ! -f "$METRICS_HISTORY" ]]; then
            echo '{"metrics": []}' > "$METRICS_HISTORY"
        fi

        local tmp_file
        tmp_file=$(mktemp)
        jq --arg ts "$timestamp" \
           --arg h "$hour" \
           --arg dow "$day_of_week" \
           --argjson cpu "${cpu:-0}" \
           --argjson mem "${mem:-0}" \
           --argjson disk "${disk:-0}" \
           --argjson procs "${proc_count:-0}" \
           --argjson conns "${net_conns:-0}" \
           --arg top "$top_proc" \
           '.metrics += [{"timestamp": $ts, "hour": $h, "day_of_week": $dow, "cpu": $cpu, "memory": $mem, "disk": $disk, "processes": $procs, "connections": $conns, "top_process": $top}] |
            if (.metrics | length) > 2880 then .metrics = .metrics[-2880:] else . end' \
           "$METRICS_HISTORY" > "$tmp_file" && mv "$tmp_file" "$METRICS_HISTORY"
    fi

    echo "$cpu $mem $disk $proc_count"
}

# ============================================================================
# Pattern Analysis - Erkennt Trends
# ============================================================================
analyze_trends() {
    if ! command -v jq &>/dev/null || [[ ! -f "$METRICS_HISTORY" ]]; then
        echo "Nicht genug Daten fuer Trendanalyse"
        return
    fi

    local metric_count
    metric_count=$(jq '.metrics | length' "$METRICS_HISTORY")

    if [[ "$metric_count" -lt 10 ]]; then
        echo -e "${YELLOW}Sammle noch Daten... ($metric_count/10 Messpunkte)${NC}"
        return
    fi

    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}      Trendanalyse                          ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    # CPU Trend (letzte 10 Messungen)
    local cpu_trend
    cpu_trend=$(jq '[.metrics[-10:][].cpu] | if length > 1 then (last - first) else 0 end' "$METRICS_HISTORY")
    if (( $(echo "$cpu_trend > 10" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${RED}CPU steigt: +${cpu_trend}% in letzten Messungen${NC}"
    elif (( $(echo "$cpu_trend < -10" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${GREEN}CPU sinkt: ${cpu_trend}% - Gut!${NC}"
    else
        echo -e "  ${BLUE}CPU stabil${NC}"
    fi

    # Memory Trend
    local mem_trend
    mem_trend=$(jq '[.metrics[-10:][].memory] | if length > 1 then (last - first) else 0 end' "$METRICS_HISTORY")
    if (( $(echo "$mem_trend > 5" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${RED}Speicher steigt: +${mem_trend}% - Moegliches Memory Leak!${NC}"
    elif (( $(echo "$mem_trend < -5" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${GREEN}Speicher sinkt: ${mem_trend}%${NC}"
    else
        echo -e "  ${BLUE}Speicher stabil${NC}"
    fi

    # Disk Trend
    local disk_trend
    disk_trend=$(jq '[.metrics[-10:][].disk] | if length > 1 then (last - first) else 0 end' "$METRICS_HISTORY")
    if (( $(echo "$disk_trend > 2" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${YELLOW}Festplatte fuellt sich: +${disk_trend}%${NC}"
    else
        echo -e "  ${BLUE}Festplatte stabil${NC}"
    fi

    echo ""

    # Peak-Stunden Analyse
    echo -e "  ${YELLOW}Typische Problem-Zeiten:${NC}"
    jq -r '
        [.metrics[] | {hour: .hour, cpu: .cpu, memory: .memory}] |
        group_by(.hour) |
        map({
            hour: .[0].hour,
            avg_cpu: ([.[].cpu] | add / length),
            avg_mem: ([.[].memory] | add / length)
        }) |
        sort_by(-.avg_cpu) |
        .[:3] |
        .[] |
        "    \(.hour):00 Uhr - CPU: \(.avg_cpu | floor)%  Speicher: \(.avg_mem | floor)%"
    ' "$METRICS_HISTORY" 2>/dev/null || echo "    Noch nicht genug Daten"

    echo ""

    # Top Resource Hogs
    echo -e "  ${YELLOW}Haeufigste Ressourcenfresser:${NC}"
    jq -r '
        [.metrics[].top_process] |
        group_by(.) |
        map({process: .[0], count: length}) |
        sort_by(-.count) |
        .[:5] |
        .[] |
        "    \(.process): \(.count)x an der Spitze"
    ' "$METRICS_HISTORY" 2>/dev/null || echo "    Noch nicht genug Daten"
}

# ============================================================================
# Predictive Alerts
# ============================================================================
predict_issues() {
    if ! command -v jq &>/dev/null || [[ ! -f "$METRICS_HISTORY" ]]; then
        return
    fi

    local current_hour
    current_hour=$(date '+%H')
    local current_dow
    current_dow=$(date '+%u')

    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}      Vorhersagen                           ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    # Check if current hour is historically problematic
    local historical_avg_cpu
    historical_avg_cpu=$(jq --arg h "$current_hour" '
        [.metrics[] | select(.hour == $h) | .cpu] |
        if length > 0 then add / length else 0 end
    ' "$METRICS_HISTORY")

    local historical_avg_mem
    historical_avg_mem=$(jq --arg h "$current_hour" '
        [.metrics[] | select(.hour == $h) | .memory] |
        if length > 0 then add / length else 0 end
    ' "$METRICS_HISTORY")

    if (( $(echo "$historical_avg_cpu > 70" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${YELLOW}VORHERSAGE: Um $current_hour:00 Uhr ist CPU typischerweise bei ${historical_avg_cpu}%${NC}"
        echo -e "  ${BLUE}-> Praeventive Massnahmen werden empfohlen${NC}"
    fi

    if (( $(echo "$historical_avg_mem > 80" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${YELLOW}VORHERSAGE: Speicher erreicht typischerweise ${historical_avg_mem}% um diese Uhrzeit${NC}"
        echo -e "  ${BLUE}-> Empfehle: Apps schliessen oder Speicher freigeben${NC}"
    fi

    # Disk prediction: at current growth rate, when will disk be full?
    local disk_growth_per_day
    disk_growth_per_day=$(jq '
        if (.metrics | length) > 48 then
            ((.metrics[-1].disk - .metrics[-48].disk) / 2)
        else 0 end
    ' "$METRICS_HISTORY")

    local current_disk
    current_disk=$(jq '.metrics[-1].disk // 0' "$METRICS_HISTORY")

    if (( $(echo "$disk_growth_per_day > 0.5" | bc -l 2>/dev/null || echo 0) )); then
        local days_until_full
        days_until_full=$(echo "scale=0; (95 - $current_disk) / $disk_growth_per_day" | bc 2>/dev/null || echo "999")
        echo -e "  ${RED}WARNUNG: Bei aktuellem Tempo ist die Festplatte in ~${days_until_full} Tagen voll!${NC}"
        echo -e "  ${BLUE}-> Empfehle: Cloud-Auslagerung aktivieren${NC}"
    fi

    echo ""
}

# ============================================================================
# Process Watchdog
# ============================================================================
watchdog_check() {
    echo -e "${CYAN}Prozess-Watchdog Check${NC}"
    echo ""

    # Find zombie processes
    local zombies
    zombies=$(ps aux 2>/dev/null | awk '$8 ~ /Z/ {print $2, $11}')
    if [[ -n "$zombies" ]]; then
        echo -e "  ${RED}Zombie-Prozesse gefunden:${NC}"
        echo "$zombies" | while read -r pid proc; do
            echo -e "    PID $pid: $proc"
        done
    fi

    # Find processes with very high memory
    echo -e "  ${YELLOW}Speicherfresser (>500MB):${NC}"
    if [[ "$(uname)" == "Darwin" ]]; then
        ps aux 2>/dev/null | awk 'NR>1 {
            mem_mb = $6/1024
            if (mem_mb > 500) printf "    %-30s %8.0fMB  CPU: %5s%%\n", $11, mem_mb, $3
        }' | sort -t$'\t' -k2 -rn | head -10
    fi

    # Find processes running longer than 24h with high CPU
    echo ""
    echo -e "  ${YELLOW}Langlaeufer mit hoher CPU:${NC}"
    ps aux 2>/dev/null | awk 'NR>1 && $3>20 {
        split($10, t, ":")
        if (length(t) >= 3 || t[1] > 60)
            printf "    %-30s CPU: %5s%%  Zeit: %s\n", $11, $3, $10
    }' | head -10

    echo ""
}

# ============================================================================
# Health Score
# ============================================================================
calculate_health_score() {
    local cpu_usage="${1:-50}"
    local mem_usage="${2:-50}"
    local disk_usage="${3:-50}"
    local proc_count="${4:-200}"

    local score=100

    # CPU deductions
    local cpu_int=${cpu_usage%.*}
    if [[ "$cpu_int" -gt 90 ]]; then
        score=$((score - 30))
    elif [[ "$cpu_int" -gt 70 ]]; then
        score=$((score - 15))
    elif [[ "$cpu_int" -gt 50 ]]; then
        score=$((score - 5))
    fi

    # Memory deductions
    local mem_int=${mem_usage%.*}
    if [[ "$mem_int" -gt 90 ]]; then
        score=$((score - 30))
    elif [[ "$mem_int" -gt 75 ]]; then
        score=$((score - 15))
    elif [[ "$mem_int" -gt 60 ]]; then
        score=$((score - 5))
    fi

    # Disk deductions
    local disk_int=${disk_usage%.*}
    if [[ "$disk_int" -gt 90 ]]; then
        score=$((score - 25))
    elif [[ "$disk_int" -gt 80 ]]; then
        score=$((score - 10))
    fi

    # Process count deductions
    if [[ "$proc_count" -gt 500 ]]; then
        score=$((score - 10))
    elif [[ "$proc_count" -gt 300 ]]; then
        score=$((score - 5))
    fi

    [[ "$score" -lt 0 ]] && score=0

    echo "$score"
}

show_health() {
    local metrics
    metrics=$(collect_metrics)
    read -r cpu mem disk procs <<< "$metrics"

    local score
    score=$(calculate_health_score "$cpu" "$mem" "$disk" "$procs")

    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}      Mac Health Score                      ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    local color=$GREEN
    local emoji="Excellent"
    if [[ "$score" -lt 50 ]]; then
        color=$RED
        emoji="Kritisch"
    elif [[ "$score" -lt 70 ]]; then
        color=$YELLOW
        emoji="Achtung"
    elif [[ "$score" -lt 85 ]]; then
        color=$BLUE
        emoji="Gut"
    fi

    echo -e "  Health Score: ${color}${score}/100 - ${emoji}${NC}"
    echo ""
    echo -e "  CPU:       ${cpu}%"
    echo -e "  Speicher:  ${mem}%"
    echo -e "  Disk:      ${disk}%"
    echo -e "  Prozesse:  ${procs}"
    echo ""

    if [[ "$score" -lt 70 ]]; then
        echo -e "  ${YELLOW}Empfehlungen:${NC}"
        [[ "${cpu%.*}" -gt 70 ]] && echo "    - CPU hoch: Schliesse nicht benoetigte Apps"
        [[ "${mem%.*}" -gt 75 ]] && echo "    - Speicher knapp: Fuehre 'mac-guardian.sh clean' aus"
        [[ "${disk%.*}" -gt 80 ]] && echo "    - Festplatte voll: Fuehre 'cloud-offload.sh scan' aus"
        [[ "$procs" -gt 400 ]] && echo "    - Zu viele Prozesse: Pruefe auf haengende Apps"
    fi
    echo ""
}

# ============================================================================
# CLI
# ============================================================================
case "${1:-health}" in
    collect)
        collect_metrics
        ;;
    trends)
        analyze_trends
        ;;
    predict)
        predict_issues
        ;;
    watchdog)
        watchdog_check
        ;;
    health)
        show_health
        ;;
    full)
        show_health
        analyze_trends
        predict_issues
        watchdog_check
        ;;
    *)
        echo "Smart Monitor - Proaktive Problemerkennung"
        echo ""
        echo "Verwendung: $0 <befehl>"
        echo ""
        echo "Befehle:"
        echo "  health    - Health Score anzeigen"
        echo "  trends    - Trendanalyse"
        echo "  predict   - Vorhersagen anzeigen"
        echo "  watchdog  - Prozess-Watchdog"
        echo "  collect   - Metriken sammeln"
        echo "  full      - Voller Bericht"
        ;;
esac
