#!/bin/bash
###############################################################################
# THERMAL GUARDIAN - Ueberhitzungsschutz
#
# Verhindert thermisches Throttling durch:
# - Proaktive CPU-Last-Reduzierung bei steigender Temperatur
# - Intelligentes Prozess-Scheduling
# - Luefter-Monitoring
# - Praeventive Kuehlung (Last reduzieren BEVOR Drosselung eintritt)
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh"

MODULE="thermal"

# Temperatur-Schwellwerte (Celsius)
TEMP_NORMAL=70
TEMP_WARM=80
TEMP_HOT=90
TEMP_CRITICAL=95

# Lese aktuelle CPU-Temperatur
get_cpu_temp() {
    # Methode 1: powermetrics (genaueste, braucht sudo)
    local temp
    temp=$(sudo powermetrics --samplers smc -i 1 -n 1 2>/dev/null | \
        grep "CPU die temperature" | awk '{print $4}')

    if [ -n "$temp" ]; then
        echo "${temp%.*}"
        return
    fi

    # Methode 2: Ueber IOKit (kein sudo noetig auf manchen Macs)
    temp=$(ioreg -r -n AppleIntelPowerManagement 2>/dev/null | \
        grep "CPU Die Temperature" | awk '{print $NF}')

    if [ -n "$temp" ]; then
        echo "$temp"
        return
    fi

    # Methode 3: kernel_task CPU als Indikator
    # kernel_task >30% CPU = System kuehlt aktiv
    local kt_cpu
    kt_cpu=$(ps aux | grep "kernel_task" | grep -v grep | awk '{print $3}' | head -1)
    if [ -n "$kt_cpu" ] && [ "${kt_cpu%.*}" -gt 30 ]; then
        echo "90"  # Geschaetzter Wert: definitiv heiss
    else
        echo "0"  # Kann nicht gemessen werden
    fi
}

# Luefter-Geschwindigkeit lesen
get_fan_speed() {
    sudo powermetrics --samplers smc -i 1 -n 1 2>/dev/null | \
        grep -i "fan" | awk '{print $NF}' | head -1
}

# CPU-Last gezielt reduzieren
reduce_cpu_load() {
    local level="$1" # light, medium, heavy

    case "$level" in
        light)
            guardian_log "$MODULE" "ACTION" "Leichte Last-Reduzierung"
            # Hintergrund-Indexierung pausieren
            sudo mdutil -i off / 2>/dev/null || true
            # Time Machine drosseln
            sudo sysctl -w debug.lowpri_throttle_enabled=1 2>/dev/null || true
            ;;
        medium)
            guardian_log "$MODULE" "ACTION" "Mittlere Last-Reduzierung"
            # Alles von light +
            reduce_cpu_load "light"
            # Low-Priority-Prozesse einschraenken
            for pid in $(ps aux -r | awk 'NR>1 && $3>20 {print $2}' | head -5); do
                local name
                name=$(ps -p "$pid" -o comm= 2>/dev/null)
                # Nur nicht-kritische Prozesse drosseln
                if ! echo "$name" | grep -qiE "WindowServer|kernel_task|loginwindow|Finder|Dock"; then
                    renice 20 "$pid" 2>/dev/null || true
                    guardian_log "$MODULE" "THROTTLE" "Renice $name (PID:$pid) auf 20"
                fi
            done
            ;;
        heavy)
            guardian_log "$MODULE" "ACTION" "Schwere Last-Reduzierung - Notfall-Kuehlung"
            reduce_cpu_load "medium"
            # Aggressive Massnahmen: Prozesse pausieren
            for pid in $(ps aux -r | awk 'NR>1 && $3>40 {print $2}' | head -3); do
                local name
                name=$(ps -p "$pid" -o comm= 2>/dev/null)
                if ! echo "$name" | grep -qiE "WindowServer|kernel_task|loginwindow|Finder|Dock|SystemUIServer"; then
                    kill -STOP "$pid" 2>/dev/null || true
                    guardian_log "$MODULE" "PAUSE" "Prozess pausiert: $name (PID:$pid)"
                    guardian_notify "Prozess pausiert" "$name pausiert fuer Kuehlung" "critical"
                    # Nach 30 Sekunden wieder aufwecken
                    (sleep 30 && kill -CONT "$pid" 2>/dev/null && \
                        guardian_log "$MODULE" "RESUME" "Prozess fortgesetzt: $name (PID:$pid)") &
                fi
            done
            ;;
    esac
}

# Spotlight nach Kuehlung wieder aktivieren
restore_after_cooling() {
    sudo mdutil -i on / 2>/dev/null || true
    guardian_log "$MODULE" "RESTORE" "Hintergrunddienste wiederhergestellt"
}

# Thermische Ueberwachung (wird vom Orchestrator aufgerufen)
thermal_check() {
    local temp
    temp=$(get_cpu_temp)

    [ "$temp" = "0" ] && return 0  # Keine Temperaturmessung moeglich

    guardian_record_metric "cpu_temp" "$temp"

    local trend
    trend=$(guardian_get_trend "cpu_temp" 18)  # Letzten 3 Minuten

    if [ "$temp" -gt "$TEMP_CRITICAL" ]; then
        guardian_log "$MODULE" "CRITICAL" "CPU ${temp}°C - KRITISCH!"
        guardian_notify "UEBERHITZUNG!" "CPU bei ${temp}°C - Notfall-Kuehlung aktiv" "critical"
        reduce_cpu_load "heavy"
        guardian_record_event "thermal_critical" "CPU ${temp}°C" "heavy_reduction"
        echo "critical"

    elif [ "$temp" -gt "$TEMP_HOT" ]; then
        guardian_log "$MODULE" "ALERT" "CPU ${temp}°C - Heiss!"
        if [ "$trend" = "rising" ]; then
            guardian_notify "CPU heiss" "${temp}°C und steigend - reduziere Last" "critical"
            reduce_cpu_load "medium"
            guardian_record_event "thermal_hot_rising" "CPU ${temp}°C trend=$trend" "medium_reduction"
        else
            reduce_cpu_load "light"
        fi
        echo "hot"

    elif [ "$temp" -gt "$TEMP_WARM" ]; then
        guardian_log "$MODULE" "WARN" "CPU ${temp}°C - Warm"
        if [ "$trend" = "rising" ]; then
            reduce_cpu_load "light"
            guardian_record_event "thermal_warm_rising" "CPU ${temp}°C trend=$trend" "light_reduction"
        fi
        echo "warm"

    else
        # Alles OK - sicherstellen dass Dienste laufen
        if [ -f "$GUARDIAN_DATA/thermal_throttled" ]; then
            restore_after_cooling
            rm -f "$GUARDIAN_DATA/thermal_throttled"
            guardian_log "$MODULE" "OK" "CPU ${temp}°C - Normal. Throttling aufgehoben."
        fi
        echo "normal"
    fi
}

# Direkter Aufruf
case "${1:-check}" in
    check)
        thermal_check
        ;;
    temp)
        echo "CPU: $(get_cpu_temp)°C"
        ;;
    fan)
        echo "Fan: $(get_fan_speed) RPM"
        ;;
    cool)
        reduce_cpu_load "${2:-medium}"
        ;;
    *)
        echo "Thermal Guardian: $0 {check|temp|fan|cool [light|medium|heavy]}"
        ;;
esac
