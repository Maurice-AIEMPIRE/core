#!/bin/bash
###############################################################################
# AI BRAIN - Intelligente Entscheidungs-Engine
#
# Analysiert Trends, lernt aus vergangenen Aktionen und trifft autonome
# Entscheidungen zur Systemoptimierung. Nutzt Pattern-Erkennung und
# adaptive Schwellwerte.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="ai-brain"
BRAIN_DATA="$GUARDIAN_DATA/brain"
mkdir -p "$BRAIN_DATA"

###############################################################################
# PATTERN-DATENBANK
# Speichert erkannte Muster und deren erfolgreiche Loesungen
###############################################################################

# Pattern speichern: Welche Aktion hat bei welchem Problem geholfen?
brain_learn() {
    local problem_type="$1" action_taken="$2" result="$3" # success/failure
    local ts
    ts=$(date +%s)
    echo "$ts|$problem_type|$action_taken|$result" >> "$BRAIN_DATA/learned_actions.csv"
    guardian_log "$MODULE" "LEARN" "Pattern: $problem_type -> $action_taken = $result"
}

# Beste Aktion fuer ein Problem finden (basierend auf Erfolgsrate)
brain_best_action() {
    local problem_type="$1"
    [ ! -f "$BRAIN_DATA/learned_actions.csv" ] && echo "default" && return

    # Zaehle Erfolge vs. Misserfolge pro Aktion
    awk -F'|' -v type="$problem_type" '
        $2 == type {
            actions[$3]++
            if ($4 == "success") successes[$3]++
        }
        END {
            best_action = "default"
            best_rate = 0
            for (a in actions) {
                rate = (successes[a]+0) / actions[a]
                if (rate > best_rate && actions[a] >= 2) {
                    best_rate = rate
                    best_action = a
                }
            }
            print best_action
        }
    ' "$BRAIN_DATA/learned_actions.csv"
}

###############################################################################
# ADAPTIVE SCHWELLWERTE
# Passt Schwellwerte basierend auf System-Baseline an
###############################################################################

# Baseline berechnen (Durchschnitt der letzten Stunde bei normaler Nutzung)
calculate_baseline() {
    local metric="$1"
    local datafile="$GUARDIAN_DATA/${metric}.csv"
    [ ! -f "$datafile" ] && echo "0" && return

    # Mittelwert der letzten 360 Datenpunkte (1 Stunde bei 10s Interval)
    tail -360 "$datafile" 2>/dev/null | awk -F',' '{sum+=$2; count++} END {
        if (count > 0) printf "%d", sum/count
        else print 0
    }'
}

# Dynamischen Schwellwert berechnen
# Basis + 1.5 * Standardabweichung = anomaler Wert
get_dynamic_threshold() {
    local metric="$1" static_threshold="$2"
    local datafile="$GUARDIAN_DATA/${metric}.csv"
    [ ! -f "$datafile" ] && echo "$static_threshold" && return

    local count
    count=$(wc -l < "$datafile" 2>/dev/null | tr -d ' ')
    [ "$count" -lt 100 ] && echo "$static_threshold" && return

    # Berechne Mean + 1.5 * StdDev
    local dynamic
    dynamic=$(tail -360 "$datafile" | awk -F',' '
        {sum+=$2; sumsq+=$2*$2; count++}
        END {
            if (count > 0) {
                mean = sum/count
                stddev = sqrt(sumsq/count - mean*mean)
                threshold = mean + 1.5 * stddev
                if (threshold > 100) threshold = 100
                printf "%d", threshold
            } else print 0
        }
    ')

    # Verwende das Minimum von statisch und dynamisch (strenger)
    if [ "$dynamic" -gt 0 ] && [ "$dynamic" -lt "$static_threshold" ]; then
        echo "$dynamic"
    else
        echo "$static_threshold"
    fi
}

###############################################################################
# VORHERSAGE-ENGINE
# Erkennt Trends und warnt BEVOR Probleme auftreten
###############################################################################

# Vorhersage: Wird ein Wert in X Minuten einen Schwellwert ueberschreiten?
predict_threshold_breach() {
    local metric="$1" threshold="$2" minutes_ahead="${3:-10}"
    local datafile="$GUARDIAN_DATA/${metric}.csv"
    [ ! -f "$datafile" ] && echo "false" && return

    local count
    count=$(wc -l < "$datafile" 2>/dev/null | tr -d ' ')
    [ "$count" -lt 30 ] && echo "false" && return

    # Lineare Regression ueber die letzten 5 Minuten (30 Datenpunkte)
    local prediction
    prediction=$(tail -30 "$datafile" | awk -F',' -v target_mins="$minutes_ahead" -v thresh="$threshold" '
        BEGIN { n=0 }
        {
            n++
            x[n] = n
            y[n] = $2
            sumx += n
            sumy += $2
            sumxy += n * $2
            sumxx += n * n
        }
        END {
            if (n < 10) { print "false"; exit }
            meanx = sumx / n
            meany = sumy / n
            # Steigung (Slope)
            slope = (sumxy - n * meanx * meany) / (sumxx - n * meanx * meanx)
            # Vorhersage: aktuelle + slope * zukuenftige_schritte
            future_steps = target_mins * 6  # 6 checks pro Minute
            predicted = y[n] + slope * future_steps
            if (predicted > thresh) print "true"
            else print "false"
        }
    ')
    echo "$prediction"
}

###############################################################################
# ANOMALIE-ERKENNUNG
# Erkennt ungewoehnliches Verhalten (Ausreisser)
###############################################################################

detect_anomaly() {
    local metric="$1" current_value="$2"
    local datafile="$GUARDIAN_DATA/${metric}.csv"
    [ ! -f "$datafile" ] && echo "false" && return

    local count
    count=$(wc -l < "$datafile" 2>/dev/null | tr -d ' ')
    [ "$count" -lt 60 ] && echo "false" && return

    # Z-Score basierte Anomalie-Erkennung
    local is_anomaly
    is_anomaly=$(tail -360 "$datafile" | awk -F',' -v current="$current_value" '
        {sum+=$2; sumsq+=$2*$2; count++}
        END {
            if (count < 30) { print "false"; exit }
            mean = sum/count
            stddev = sqrt(sumsq/count - mean*mean)
            if (stddev < 1) stddev = 1
            zscore = (current - mean) / stddev
            if (zscore > 2.5 || zscore < -2.5) print "true"
            else print "false"
        }
    ')
    echo "$is_anomaly"
}

###############################################################################
# KORRELATIONS-ENGINE
# Erkennt zusammenhaengende Probleme
###############################################################################

# Sind CPU und RAM gleichzeitig hoch? -> Wahrscheinlich eine einzelne App
detect_correlated_issues() {
    local cpu_high="$1" ram_high="$2" temp_high="$3" disk_high="$4"

    if [ "$cpu_high" = "true" ] && [ "$ram_high" = "true" ]; then
        echo "app_overload"  # Eine App frisst alles
    elif [ "$cpu_high" = "true" ] && [ "$temp_high" = "true" ]; then
        echo "thermal_throttle"  # CPU heiss -> Drosselung
    elif [ "$ram_high" = "true" ] && [ "$disk_high" = "true" ]; then
        echo "memory_pressure"  # Swap-Kaskade
    elif [ "$cpu_high" = "true" ]; then
        echo "cpu_bound"
    elif [ "$ram_high" = "true" ]; then
        echo "memory_bound"
    elif [ "$temp_high" = "true" ]; then
        echo "thermal_issue"
    elif [ "$disk_high" = "true" ]; then
        echo "disk_issue"
    else
        echo "none"
    fi
}

###############################################################################
# ENTSCHEIDUNGS-ENGINE
# Waehlt die beste Aktion basierend auf allen Daten
###############################################################################

# Hauptentscheidungsfunktion: Was soll jetzt getan werden?
brain_decide() {
    local cpu_pct="$1" ram_pct="$2" swap_mb="$3" temp="$4" disk_pct="$5"

    # Config laden
    local cpu_warn=${CPU_WARN_THRESHOLD:-80}
    local cpu_crit=${CPU_CRITICAL_THRESHOLD:-95}
    local ram_warn=${RAM_WARN_THRESHOLD:-85}
    local ram_crit=${RAM_CRITICAL_THRESHOLD:-93}

    # Adaptive Schwellwerte
    local dyn_cpu_warn dyn_ram_warn
    dyn_cpu_warn=$(get_dynamic_threshold "cpu_total" "$cpu_warn")
    dyn_ram_warn=$(get_dynamic_threshold "ram_used_pct" "$ram_warn")

    # Trend-Analyse
    local cpu_trend ram_trend
    cpu_trend=$(guardian_get_trend "cpu_total" 30)
    ram_trend=$(guardian_get_trend "ram_used_pct" 30)

    # Vorhersage
    local cpu_breach_predicted ram_breach_predicted
    cpu_breach_predicted=$(predict_threshold_breach "cpu_total" "$cpu_crit" 5)
    ram_breach_predicted=$(predict_threshold_breach "ram_used_pct" "$ram_crit" 5)

    # Anomalie-Check
    local cpu_anomaly ram_anomaly
    cpu_anomaly=$(detect_anomaly "cpu_total" "$cpu_pct")
    ram_anomaly=$(detect_anomaly "ram_used_pct" "$ram_pct")

    # Korrelation
    local cpu_high ram_high temp_high disk_high
    [ "$cpu_pct" -gt "$cpu_warn" ] && cpu_high="true" || cpu_high="false"
    [ "$ram_pct" -gt "$ram_warn" ] && ram_high="true" || ram_high="false"
    [ -n "$temp" ] && [ "$temp" -gt 85 ] && temp_high="true" || temp_high="false"
    [ "$disk_pct" -gt 90 ] && disk_high="true" || disk_high="false"

    local root_cause
    root_cause=$(detect_correlated_issues "$cpu_high" "$ram_high" "$temp_high" "$disk_high")

    # Entscheidungsbaum
    local decision="none"
    local urgency="low"
    local reason=""

    # STUFE 4: NOTFALL - Sofort handeln
    if [ "$cpu_pct" -gt "$cpu_crit" ] && [ "$ram_pct" -gt "$ram_crit" ]; then
        decision="emergency_kill"
        urgency="critical"
        reason="CPU ${cpu_pct}% UND RAM ${ram_pct}% - System-Notfall"

    # STUFE 3: KRITISCH - Aggressives Eingreifen
    elif [ "$cpu_pct" -gt "$cpu_crit" ]; then
        local best
        best=$(brain_best_action "cpu_critical")
        decision="${best:-kill_cpu_hogs}"
        urgency="high"
        reason="CPU bei ${cpu_pct}% (Schwelle: $cpu_crit%)"

    elif [ "$ram_pct" -gt "$ram_crit" ]; then
        decision="free_memory_aggressive"
        urgency="high"
        reason="RAM bei ${ram_pct}% (Schwelle: $ram_crit%)"

    # STUFE 2: WARNUNG + PRAEVENTION
    elif [ "$cpu_breach_predicted" = "true" ] || [ "$ram_breach_predicted" = "true" ]; then
        decision="preventive_action"
        urgency="medium"
        reason="Vorhersage: Schwellwert-Ueberschreitung in 5 Minuten (CPU-Trend: $cpu_trend, RAM-Trend: $ram_trend)"

    elif [ "$cpu_anomaly" = "true" ] || [ "$ram_anomaly" = "true" ]; then
        decision="investigate_anomaly"
        urgency="medium"
        reason="Anomalie erkannt (CPU: $cpu_anomaly, RAM: $ram_anomaly)"

    elif [ "$cpu_pct" -gt "$dyn_cpu_warn" ] && [ "$cpu_trend" = "rising" ]; then
        decision="soft_intervention"
        urgency="medium"
        reason="CPU ${cpu_pct}% und steigend (dyn. Schwelle: $dyn_cpu_warn%)"

    elif [ "$ram_pct" -gt "$dyn_ram_warn" ] && [ "$ram_trend" = "rising" ]; then
        decision="free_memory_soft"
        urgency="medium"
        reason="RAM ${ram_pct}% und steigend (dyn. Schwelle: $dyn_ram_warn%)"

    # Thermisch
    elif [ "$temp_high" = "true" ]; then
        decision="thermal_mitigation"
        urgency="high"
        reason="Temperatur ${temp}C - Ueberhitzungsgefahr"

    # STUFE 1: WARTUNG
    elif [ "$root_cause" = "memory_pressure" ]; then
        decision="free_memory_soft"
        urgency="low"
        reason="Memory Pressure erkannt (RAM: $ram_pct%, Swap: ${swap_mb}MB)"
    fi

    # Ergebnis ausgeben (wird vom Orchestrator gelesen)
    echo "${decision}|${urgency}|${reason}|${root_cause}"

    guardian_log "$MODULE" "DECIDE" \
        "Decision=$decision Urgency=$urgency Cause=$root_cause CPU=${cpu_pct}% RAM=${ram_pct}% Temp=${temp}C"
}

###############################################################################
# FEEDBACK-LOOP: War die letzte Aktion erfolgreich?
###############################################################################

brain_evaluate_action() {
    local action="$1" metric_before="$2" metric_after="$3"

    if [ "$metric_after" -lt "$metric_before" ]; then
        local improvement=$((metric_before - metric_after))
        brain_learn "$(echo "$action" | cut -d'_' -f1)" "$action" "success"
        guardian_log "$MODULE" "FEEDBACK" "Aktion '$action' erfolgreich: $metric_before% -> $metric_after% (-${improvement}%)"
        return 0
    else
        brain_learn "$(echo "$action" | cut -d'_' -f1)" "$action" "failure"
        guardian_log "$MODULE" "FEEDBACK" "Aktion '$action' wirkungslos: $metric_before% -> $metric_after%"
        return 1
    fi
}

###############################################################################
# TAGES-REPORT generieren
###############################################################################

brain_daily_report() {
    local report_file="$GUARDIAN_DATA/daily-report-$(date +%Y%m%d).txt"

    {
        echo "═══════════════════════════════════════"
        echo "  MAC GUARDIAN - TAGESREPORT"
        echo "  $(date '+%Y-%m-%d')"
        echo "═══════════════════════════════════════"
        echo ""

        # Metriken-Zusammenfassung
        for metric in cpu_total ram_used_pct cpu_temp disk_used_pct dns_latency; do
            local datafile="$GUARDIAN_DATA/${metric}.csv"
            [ ! -f "$datafile" ] && continue
            local stats
            stats=$(tail -8640 "$datafile" | awk -F',' '
                {sum+=$2; if($2>max)max=$2; if(min==""||$2<min)min=$2; count++}
                END {printf "Avg: %d, Max: %d, Min: %d", sum/count, max, min}
            ')
            echo "  ${metric}: $stats"
        done

        echo ""

        # Aktionen heute
        local today
        today=$(date +%Y%m%d)
        local action_count
        action_count=$(grep -c "\[$today" "$GUARDIAN_HISTORY/events.log" 2>/dev/null || echo 0)
        echo "  Automatische Eingriffe heute: $action_count"

        if [ -f "$BRAIN_DATA/learned_actions.csv" ]; then
            local total_actions
            total_actions=$(wc -l < "$BRAIN_DATA/learned_actions.csv" | tr -d ' ')
            local success_rate
            success_rate=$(awk -F'|' '
                {total++; if($4=="success") success++}
                END {if(total>0) printf "%d%%", success*100/total; else print "N/A"}
            ' "$BRAIN_DATA/learned_actions.csv")
            echo "  Gesamt gelernte Patterns: $total_actions"
            echo "  Erfolgsrate: $success_rate"
        fi

    } > "$report_file"

    guardian_log "$MODULE" "REPORT" "Tagesreport erstellt: $report_file"
    cat "$report_file"
}

# Wenn direkt aufgerufen
case "${1:-}" in
    decide)
        brain_decide "${2:-0}" "${3:-0}" "${4:-0}" "${5:-0}" "${6:-0}"
        ;;
    report)
        brain_daily_report
        ;;
    learn)
        brain_learn "$2" "$3" "$4"
        ;;
    *)
        echo "AI Brain Module"
        echo "Usage: $0 {decide|report|learn}"
        ;;
esac
