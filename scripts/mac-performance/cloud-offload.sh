#!/usr/bin/env bash
# ============================================================================
# Cloud Offload - Dateien automatisch auf Hetzner Storage Box auslagern
# Bei Speicherprobleme werden grosse/alte Dateien auf den Cloud-Server verschoben
# ============================================================================
set -euo pipefail

GUARDIAN_DIR="$HOME/.mac-guardian"
CONFIG_FILE="$GUARDIAN_DIR/config.json"
LOG_DIR="$GUARDIAN_DIR/logs"
OFFLOAD_DB="$GUARDIAN_DIR/offloaded-files.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default offload paths
OFFLOAD_SOURCES=(
    "$HOME/Downloads"
    "$HOME/Documents"
    "$HOME/Desktop"
    "$HOME/Movies"
    "$HOME/Music"
    "$HOME/Pictures"
    "$HOME/Library/Application Support/MobileSync/Backup"
)

# File patterns to offload (large/old files)
OFFLOAD_PATTERNS=(
    "*.dmg"
    "*.iso"
    "*.zip"
    "*.tar.gz"
    "*.tar.bz2"
    "*.rar"
    "*.7z"
    "*.mp4"
    "*.mov"
    "*.avi"
    "*.mkv"
    "*.pkg"
    "*.app.zip"
    "*.vmdk"
    "*.vdi"
    "*.ova"
)

# Minimum file age (days) for auto-offload
MIN_AGE_DAYS=14
# Minimum file size (MB) for auto-offload
MIN_SIZE_MB=100

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [OFFLOAD] [$level] $msg" >> "$LOG_DIR/offload.log"

    case "$level" in
        ERROR)   echo -e "${RED}[$level] $msg${NC}" ;;
        WARN)    echo -e "${YELLOW}[$level] $msg${NC}" ;;
        ACTION)  echo -e "${GREEN}[$level] $msg${NC}" ;;
        INFO)    echo -e "${BLUE}[$level] $msg${NC}" ;;
        *)       echo -e "${CYAN}[$level] $msg${NC}" ;;
    esac
}

# ============================================================================
# Configuration
# ============================================================================
get_hetzner_config() {
    if ! command -v jq &>/dev/null; then
        log ERROR "jq wird benoetigt. Installiere mit: brew install jq"
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config nicht gefunden. Fuehre zuerst mac-guardian.sh aus."
        exit 1
    fi

    HETZNER_HOST=$(jq -r '.hetzner_storage_box // ""' "$CONFIG_FILE")
    HETZNER_USER=$(jq -r '.hetzner_user // ""' "$CONFIG_FILE")
    HETZNER_PORT=$(jq -r '.hetzner_port // "23"' "$CONFIG_FILE")
    HETZNER_PATH=$(jq -r '.hetzner_remote_path // "/backup/mac"' "$CONFIG_FILE")
}

setup_hetzner() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  Hetzner Storage Box Konfiguration         ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    read -rp "Hetzner Storage Box Host (z.B. uXXXXXX.your-storagebox.de): " host
    read -rp "Hetzner Benutzername: " user
    read -rp "Hetzner Port (Standard: 23): " port
    port=${port:-23}
    read -rp "Remote-Pfad (Standard: /backup/mac): " remote_path
    remote_path=${remote_path:-/backup/mac}

    # Update config
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg host "$host" \
       --arg user "$user" \
       --arg port "$port" \
       --arg path "$remote_path" \
       '.hetzner_storage_box = $host |
        .hetzner_user = $user |
        .hetzner_port = $port |
        .hetzner_remote_path = $path |
        .cloud_offload_enabled = true' \
       "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"

    log ACTION "Hetzner Storage Box konfiguriert: $user@$host:$port"

    # Test connection
    echo ""
    echo -e "${YELLOW}Teste Verbindung...${NC}"
    if ssh -p "$port" -o ConnectTimeout=10 -o BatchMode=yes "$user@$host" "echo 'Verbindung OK'" 2>/dev/null; then
        log ACTION "Verbindung erfolgreich!"

        # Setup SSH key if not already done
        setup_ssh_key "$user" "$host" "$port"
    else
        log WARN "Verbindung fehlgeschlagen. SSH-Key muss noch eingerichtet werden."
        setup_ssh_key "$user" "$host" "$port"
    fi
}

setup_ssh_key() {
    local user="$1"
    local host="$2"
    local port="$3"

    if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]] && [[ ! -f "$HOME/.ssh/id_rsa.pub" ]]; then
        echo -e "${YELLOW}Erstelle SSH-Key...${NC}"
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "mac-guardian-offload"
    fi

    local pub_key
    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        pub_key="$HOME/.ssh/id_ed25519.pub"
    else
        pub_key="$HOME/.ssh/id_rsa.pub"
    fi

    echo -e "${YELLOW}Kopiere SSH-Key auf Hetzner Storage Box...${NC}"
    echo -e "${BLUE}Du wirst nach dem Passwort gefragt:${NC}"

    # Hetzner Storage Box uses a special method for SSH keys
    cat "$pub_key" | ssh -p "$port" "$user@$host" "mkdir -p .ssh && cat >> .ssh/authorized_keys" 2>/dev/null || {
        log WARN "Automatisches Kopieren fehlgeschlagen."
        echo ""
        echo "Kopiere den Key manuell:"
        echo "  cat $pub_key | ssh -p $port $user@$host 'mkdir -p .ssh && cat >> .ssh/authorized_keys'"
    }
}

# ============================================================================
# File Discovery
# ============================================================================
find_offloadable_files() {
    local target_dir="${1:-}"
    local min_size="${2:-$MIN_SIZE_MB}"
    local min_age="${3:-$MIN_AGE_DAYS}"

    log INFO "Suche Dateien zum Auslagern (>= ${min_size}MB, >= ${min_age} Tage alt)..."

    local total_size=0
    local file_count=0

    local search_dirs=()
    if [[ -n "$target_dir" ]]; then
        search_dirs=("$target_dir")
    else
        search_dirs=("${OFFLOAD_SOURCES[@]}")
    fi

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue

        while IFS= read -r -d '' file; do
            local size_mb
            size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')

            if [[ "$size_mb" -ge "$min_size" ]]; then
                local mod_date
                mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat --format="%y" "$file" 2>/dev/null | cut -d' ' -f1)
                echo -e "  ${YELLOW}${size_mb}MB${NC}\t${mod_date}\t$file"
                total_size=$((total_size + size_mb))
                file_count=$((file_count + 1))
            fi
        done < <(find "$dir" -maxdepth 3 -type f -mtime "+${min_age}" -size "+${min_size}M" -print0 2>/dev/null)

        # Also check specific patterns regardless of age
        for pattern in "${OFFLOAD_PATTERNS[@]}"; do
            while IFS= read -r -d '' file; do
                local size_mb
                size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')
                if [[ "$size_mb" -ge "$min_size" ]]; then
                    local mod_date
                    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat --format="%y" "$file" 2>/dev/null | cut -d' ' -f1)
                    echo -e "  ${YELLOW}${size_mb}MB${NC}\t${mod_date}\t$file"
                    total_size=$((total_size + size_mb))
                    file_count=$((file_count + 1))
                fi
            done < <(find "$dir" -maxdepth 3 -type f -name "$pattern" -size "+${min_size}M" -print0 2>/dev/null)
        done
    done

    echo ""
    echo -e "${CYAN}Gefunden: $file_count Dateien, ~${total_size}MB auslagerbar${NC}"
}

# ============================================================================
# Offload Operations
# ============================================================================
offload_file() {
    local file="$1"
    local remote_base="$2"

    if [[ ! -f "$file" ]]; then
        log ERROR "Datei nicht gefunden: $file"
        return 1
    fi

    local rel_path
    rel_path=$(echo "$file" | sed "s|$HOME/||")
    local remote_path="${remote_base}/${rel_path}"
    local remote_dir
    remote_dir=$(dirname "$remote_path")

    local size_mb
    size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')

    log ACTION "Lade hoch: $file (${size_mb}MB) -> $remote_path"

    # Create remote directory
    ssh -p "$HETZNER_PORT" "${HETZNER_USER}@${HETZNER_HOST}" "mkdir -p '$remote_dir'" 2>/dev/null || true

    # Upload with rsync (resume support, compression)
    if command -v rsync &>/dev/null; then
        rsync -avz --progress --partial \
            -e "ssh -p $HETZNER_PORT" \
            "$file" \
            "${HETZNER_USER}@${HETZNER_HOST}:${remote_path}" 2>/dev/null
    else
        scp -P "$HETZNER_PORT" "$file" "${HETZNER_USER}@${HETZNER_HOST}:${remote_path}" 2>/dev/null
    fi

    if [[ $? -eq 0 ]]; then
        # Verify upload
        local remote_size
        remote_size=$(ssh -p "$HETZNER_PORT" "${HETZNER_USER}@${HETZNER_HOST}" "du -m '$remote_path' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "0")

        if [[ "$remote_size" -ge "$size_mb" ]] || [[ "$((remote_size + 1))" -ge "$size_mb" ]]; then
            log ACTION "Upload erfolgreich verifiziert"

            # Track offloaded file
            track_offloaded_file "$file" "$remote_path" "$size_mb"

            return 0
        else
            log ERROR "Upload-Verifikation fehlgeschlagen (lokal: ${size_mb}MB, remote: ${remote_size}MB)"
            return 1
        fi
    else
        log ERROR "Upload fehlgeschlagen: $file"
        return 1
    fi
}

offload_and_remove() {
    local file="$1"
    local remote_base="$2"

    if offload_file "$file" "$remote_base"; then
        local size_mb
        size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')

        # Create a symlink placeholder (optional)
        local placeholder="${file}.offloaded"
        echo "Ausgelagert auf Hetzner: $(date '+%Y-%m-%d %H:%M:%S')" > "$placeholder"
        echo "Remote: ${HETZNER_USER}@${HETZNER_HOST}:${remote_base}/$(echo "$file" | sed "s|$HOME/||")" >> "$placeholder"

        # Remove local file
        rm -f "$file"

        log ACTION "Lokale Datei entfernt: $file (${size_mb}MB freigegeben)"
        return 0
    fi
    return 1
}

track_offloaded_file() {
    local local_path="$1"
    local remote_path="$2"
    local size_mb="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ ! -f "$OFFLOAD_DB" ]]; then
        echo '{"files": []}' > "$OFFLOAD_DB"
    fi

    local tmp_file
    tmp_file=$(mktemp)
    jq --arg local "$local_path" \
       --arg remote "$remote_path" \
       --arg size "$size_mb" \
       --arg ts "$timestamp" \
       '.files += [{"local_path": $local, "remote_path": $remote, "size_mb": ($size | tonumber), "offloaded_at": $ts}]' \
       "$OFFLOAD_DB" > "$tmp_file" && mv "$tmp_file" "$OFFLOAD_DB"
}

# ============================================================================
# Auto Offload (called by Guardian daemon)
# ============================================================================
auto_offload() {
    get_hetzner_config

    if [[ -z "$HETZNER_HOST" ]] || [[ -z "$HETZNER_USER" ]]; then
        log WARN "Hetzner nicht konfiguriert. Fuehre 'cloud-offload.sh setup' aus."
        return 1
    fi

    local disk_usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    local disk_int=${disk_usage%.*}

    if [[ "$disk_int" -lt 80 ]]; then
        log INFO "Disk bei ${disk_usage}% - Keine Auslagerung noetig"
        return 0
    fi

    log ACTION "Disk bei ${disk_usage}% - Starte automatische Auslagerung"

    local freed_total=0

    for dir in "${OFFLOAD_SOURCES[@]}"; do
        [[ ! -d "$dir" ]] && continue

        while IFS= read -r -d '' file; do
            local size_mb
            size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')

            if offload_and_remove "$file" "$HETZNER_PATH"; then
                freed_total=$((freed_total + size_mb))
            fi

            # Check if we freed enough
            local new_disk
            new_disk=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
            if [[ "${new_disk%.*}" -lt 75 ]]; then
                log ACTION "Disk jetzt bei ${new_disk}% - Genug freigegeben"
                break 2
            fi
        done < <(find "$dir" -maxdepth 3 -type f -mtime +30 -size +200M -print0 2>/dev/null | head -z -20)
    done

    log ACTION "Automatische Auslagerung: ${freed_total}MB freigegeben"
}

# ============================================================================
# Restore from Cloud
# ============================================================================
restore_file() {
    local remote_path="$1"
    local local_path="${2:-}"

    get_hetzner_config

    if [[ -z "$local_path" ]]; then
        # Derive local path from remote
        local_path="$HOME/$(echo "$remote_path" | sed "s|$HETZNER_PATH/||")"
    fi

    local local_dir
    local_dir=$(dirname "$local_path")
    mkdir -p "$local_dir"

    log ACTION "Stelle wieder her: $remote_path -> $local_path"

    if command -v rsync &>/dev/null; then
        rsync -avz --progress --partial \
            -e "ssh -p $HETZNER_PORT" \
            "${HETZNER_USER}@${HETZNER_HOST}:${remote_path}" \
            "$local_path"
    else
        scp -P "$HETZNER_PORT" "${HETZNER_USER}@${HETZNER_HOST}:${remote_path}" "$local_path"
    fi

    if [[ $? -eq 0 ]]; then
        log ACTION "Wiederherstellung erfolgreich: $local_path"
        # Remove placeholder if exists
        rm -f "${local_path}.offloaded" 2>/dev/null || true
    else
        log ERROR "Wiederherstellung fehlgeschlagen"
    fi
}

list_offloaded() {
    if [[ ! -f "$OFFLOAD_DB" ]]; then
        echo "Keine ausgelagerten Dateien."
        return
    fi

    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}     Ausgelagerte Dateien                   ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    local total_size
    total_size=$(jq '[.files[].size_mb] | add // 0' "$OFFLOAD_DB")

    jq -r '.files[] | "\(.size_mb)MB\t\(.offloaded_at)\t\(.local_path)"' "$OFFLOAD_DB" | \
        while IFS=$'\t' read -r size date path; do
            echo -e "  ${YELLOW}${size}${NC}\t${date}\t${path}"
        done

    echo ""
    echo -e "${GREEN}Gesamt ausgelagert: ${total_size}MB${NC}"
}

# ============================================================================
# Sync Operations
# ============================================================================
sync_to_cloud() {
    local source_dir="${1:-$HOME}"
    get_hetzner_config

    log ACTION "Synchronisiere $source_dir -> Hetzner"

    rsync -avz --progress --partial \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='.DS_Store' \
        --exclude='*.tmp' \
        --exclude='.Trash' \
        -e "ssh -p $HETZNER_PORT" \
        "$source_dir/" \
        "${HETZNER_USER}@${HETZNER_HOST}:${HETZNER_PATH}/sync/$(basename "$source_dir")/"

    log ACTION "Synchronisierung abgeschlossen"
}

# ============================================================================
# CLI
# ============================================================================
usage() {
    echo -e "${CYAN}Cloud Offload - Hetzner Storage Box Manager${NC}"
    echo ""
    echo "Verwendung: $0 <befehl>"
    echo ""
    echo "Befehle:"
    echo "  setup          - Hetzner Storage Box konfigurieren"
    echo "  scan [pfad]    - Auslagerbare Dateien finden"
    echo "  auto           - Automatische Auslagerung (fuer Guardian)"
    echo "  offload <datei> - Einzelne Datei auslagern"
    echo "  move <datei>   - Datei auslagern UND lokal entfernen"
    echo "  restore <pfad> - Datei von Cloud wiederherstellen"
    echo "  list           - Ausgelagerte Dateien anzeigen"
    echo "  sync <pfad>    - Ordner mit Cloud synchronisieren"
    echo "  interactive    - Interaktiver Modus"
    echo ""
}

interactive_mode() {
    get_hetzner_config

    if [[ -z "$HETZNER_HOST" ]]; then
        echo -e "${YELLOW}Hetzner noch nicht konfiguriert. Starte Setup...${NC}"
        setup_hetzner
        get_hetzner_config
    fi

    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}     Cloud Offload - Interaktiv             ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    echo "Suche auslagerbare Dateien..."
    echo ""
    find_offloadable_files "" 50 7

    echo ""
    read -rp "Moechtest du diese Dateien auslagern? (j/n/auswahl): " choice

    case "$choice" in
        j|J|ja|Ja)
            log ACTION "Starte Batch-Auslagerung..."
            for dir in "${OFFLOAD_SOURCES[@]}"; do
                [[ ! -d "$dir" ]] && continue
                while IFS= read -r -d '' file; do
                    local size_mb
                    size_mb=$(du -m "$file" 2>/dev/null | awk '{print $1}')
                    if [[ "$size_mb" -ge 50 ]]; then
                        read -rp "  Auslagern: $file (${size_mb}MB)? (j/n/verschieben): " confirm
                        case "$confirm" in
                            j|J) offload_file "$file" "$HETZNER_PATH" ;;
                            v|V|verschieben) offload_and_remove "$file" "$HETZNER_PATH" ;;
                            *) echo "  Uebersprungen" ;;
                        esac
                    fi
                done < <(find "$dir" -maxdepth 3 -type f -mtime +7 -size +50M -print0 2>/dev/null)
            done
            ;;
        *)
            echo "Abgebrochen."
            ;;
    esac
}

# ============================================================================
# Entry Point
# ============================================================================
mkdir -p "$GUARDIAN_DIR" "$LOG_DIR"

case "${1:-help}" in
    setup)
        setup_hetzner
        ;;
    scan)
        find_offloadable_files "${2:-}" "${3:-100}" "${4:-14}"
        ;;
    auto)
        auto_offload
        ;;
    offload)
        get_hetzner_config
        offload_file "${2:?Datei angeben}" "$HETZNER_PATH"
        ;;
    move)
        get_hetzner_config
        offload_and_remove "${2:?Datei angeben}" "$HETZNER_PATH"
        ;;
    restore)
        restore_file "${2:?Remote-Pfad angeben}" "${3:-}"
        ;;
    list)
        list_offloaded
        ;;
    sync)
        sync_to_cloud "${2:?Pfad angeben}"
        ;;
    interactive)
        interactive_mode
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
