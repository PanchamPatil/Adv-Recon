#!/bin/bash

set -uo pipefail

START_TIME=$(date +%s)

# ==========================================
# ADV-RECON  ::  By Pancham Patil
# ==========================================

# --- Colors ---
C_RESET='\033[0m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'

log_info ()  { echo -e "${C_BLUE}[*]${C_RESET} $1"; }
log_ok ()    { echo -e "${C_GREEN}[+]${C_RESET} $1"; }
log_warn ()  { echo -e "${C_YELLOW}[!]${C_RESET} $1"; }
log_err ()   { echo -e "${C_RED}[x]${C_RESET} $1"; }

echo "====================================================="
echo "   █████╗ ██████╗ ██╗   ██╗      ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗"
echo "  ██╔══██╗██╔══██╗██║   ██║      ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║"
echo "  ███████║██║  ██║██║   ██║█████╗██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║"
echo "  ██╔══██║██║  ██║╚██╗ ██╔╝╚════╝██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║"
echo "  ██║  ██║██████╔╝ ╚████╔╝       ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║"
echo "  ╚═╝  ╚═╝╚═════╝   ╚═══╝        ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝"
echo ""
echo "        Advanced Bug Bounty Recon & Scan Framework"
echo "                 By Pancham Patil & TilakSingh Rana and Spectator (Eshaan Pilar) 🔥"
echo "====================================================="

# --- Check input ---
if [ $# -ne 1 ]; then
    echo ""
    echo "Usage: ./Adv-Recon.sh example.com"
    exit 1
fi

DOMAIN=$1

# ==========================================
# ADVANCED AUTO INSTALLER
# ==========================================

echo ""
echo -e "${C_CYAN}=====================================================${C_RESET}"
echo -e "${C_CYAN}        Adv-Recon :: Advanced Dependency Installer${C_RESET}"
echo -e "${C_CYAN}=====================================================${C_RESET}"

OS_TYPE="$(uname -s)"
PKG_MANAGER=""
PKG_INSTALL=""
PKG_UPDATE=""
SUDO=""

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        log_warn "Not root and sudo not found. System package installs may fail."
    fi
fi

detect_pkg_manager () {
    if [ "$OS_TYPE" = "Darwin" ]; then
        PKG_MANAGER="brew"; PKG_INSTALL="brew install"; PKG_UPDATE="brew update"; SUDO=""
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"; PKG_INSTALL="$SUDO apt-get install -y"; PKG_UPDATE="$SUDO apt-get update -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"; PKG_INSTALL="$SUDO dnf install -y"; PKG_UPDATE="$SUDO dnf makecache -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"; PKG_INSTALL="$SUDO yum install -y"; PKG_UPDATE="$SUDO yum makecache -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"; PKG_INSTALL="$SUDO pacman -S --noconfirm"; PKG_UPDATE="$SUDO pacman -Sy"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"; PKG_INSTALL="$SUDO zypper install -y"; PKG_UPDATE="$SUDO zypper refresh"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"; PKG_INSTALL="$SUDO apk add"; PKG_UPDATE="$SUDO apk update"
    else
        PKG_MANAGER="unknown"
    fi
}

detect_pkg_manager

log_info "OS detected      : $OS_TYPE"
log_info "Package manager  : $PKG_MANAGER"
log_info "Architecture     : $(uname -m)"

[ "$PKG_MANAGER" = "unknown" ] && log_warn "Unknown package manager. Base packages must be installed manually."

sys_install () {
    local pkg="$1"
    [ "$PKG_MANAGER" = "unknown" ] && return 1
    eval "$PKG_INSTALL $pkg" >/dev/null 2>&1
}

ensure_binary () {
    local bin="$1" pkg="${2:-$1}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        log_info "Installing base dependency: $pkg"
        sys_install "$pkg" && log_ok "$bin installed" || log_warn "Failed to install $bin"
    fi
}

if [ "$PKG_MANAGER" != "unknown" ] && [ "$PKG_MANAGER" != "brew" ]; then
    log_info "Refreshing package index..."
    eval "$PKG_UPDATE" >/dev/null 2>&1 || log_warn "Package index refresh failed (continuing)."
fi

ensure_binary curl curl
ensure_binary git git
ensure_binary tar tar
ensure_binary unzip unzip
ensure_binary flock util-linux

install_go () {
    if command -v go >/dev/null 2>&1; then
        log_ok "Go already installed: $(go version | awk '{print $3}')"
        return 0
    fi
    log_info "Go not found. Fetching latest version..."
    local GO_LATEST GOARCH GOOS
    GO_LATEST="$(curl -sL 'https://go.dev/VERSION?m=text' 2>/dev/null | head -n1)"
    [ -z "$GO_LATEST" ] && GO_LATEST="go1.22.5"
    case "$(uname -m)" in
        x86_64|amd64)   GOARCH="amd64" ;;
        aarch64|arm64)  GOARCH="arm64" ;;
        armv7l|armv6l)  GOARCH="armv6l" ;;
        i386|i686)      GOARCH="386" ;;
        *)              GOARCH="amd64" ;;
    esac
    if [ "$OS_TYPE" = "Darwin" ]; then GOOS="darwin"; else GOOS="linux"; fi
    local TARBALL="${GO_LATEST}.${GOOS}-${GOARCH}.tar.gz"
    log_info "Downloading $TARBALL ..."
    cd /tmp
    if curl -sL "https://go.dev/dl/${TARBALL}" -o go.tar.gz; then
        $SUDO rm -rf /usr/local/go
        $SUDO tar -C /usr/local -xzf go.tar.gz
        rm -f go.tar.gz
        log_ok "Go ${GO_LATEST} installed"
    else
        log_err "Failed to download Go."
    fi
    cd - >/dev/null
}

install_go

export PATH="$PATH:/usr/local/go/bin"
export GOPATH="${GOPATH:-$HOME/go}"
export GOBIN="$GOPATH/bin"
export PATH="$PATH:$GOBIN"
mkdir -p "$GOBIN"

persist_path () {
    local rcfile="$HOME/.bashrc"
    [ -n "${ZSH_VERSION:-}" ] && rcfile="$HOME/.zshrc"
    if ! grep -q "Added by Adv-Recon" "$rcfile" 2>/dev/null; then
        {
            echo ""
            echo "# Added by Adv-Recon"
            echo "export PATH=\$PATH:/usr/local/go/bin"
            echo "export GOPATH=\$HOME/go"
            echo "export PATH=\$PATH:\$GOPATH/bin"
        } >> "$rcfile"
        log_ok "PATH persisted to $rcfile"
    fi
}
persist_path

declare -A GO_TOOLS=(
    [subfinder]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [katana]="github.com/projectdiscovery/katana/cmd/katana@latest"
    [assetfinder]="github.com/tomnomnom/assetfinder@latest"
    [gau]="github.com/lc/gau/v2/cmd/gau@latest"
    [waybackurls]="github.com/tomnomnom/waybackurls@latest"
    [qsreplace]="github.com/tomnomnom/qsreplace@latest"
    [gf]="github.com/tomnomnom/gf@latest"
)

REQUIRED_TOOLS=(subfinder httpx katana assetfinder gau waybackurls qsreplace gf curl)

install_go_tool () {
    local name="$1" path="$2"
    command -v "$name" >/dev/null 2>&1 && return 0
    if go install -v "$path" >/dev/null 2>&1; then
        echo -e "${C_GREEN}[+]${C_RESET} Installed: $name"
    else
        echo -e "${C_RED}[x]${C_RESET} Failed:    $name"
    fi
}
export -f install_go_tool
export C_GREEN C_RED C_RESET

echo ""
log_info "Installing missing Go tools (parallel)..."

PIDS=()
for name in "${!GO_TOOLS[@]}"; do
    if ! command -v "$name" >/dev/null 2>&1; then
        install_go_tool "$name" "${GO_TOOLS[$name]}" &
        PIDS+=("$!")
    fi
done
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

export PATH="$PATH:/usr/local/go/bin:$GOBIN"

setup_gf_patterns () {
    log_info "Setting up gf patterns..."
    mkdir -p "$HOME/.gf"
    if [ ! -d /tmp/gf-src ]; then
        git clone -q https://github.com/tomnomnom/gf /tmp/gf-src 2>/dev/null || true
    fi
    cp -r /tmp/gf-src/examples/* "$HOME/.gf/" 2>/dev/null || true
    if [ ! -d /tmp/Gf-Patterns ]; then
        git clone -q https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns 2>/dev/null || true
    fi
    cp -r /tmp/Gf-Patterns/*.json "$HOME/.gf/" 2>/dev/null || true
    local count
    count=$(find "$HOME/.gf" -name '*.json' 2>/dev/null | wc -l)
    log_ok "gf patterns ready ($count patterns)"
}
setup_gf_patterns

echo ""
echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"
echo -e "${C_CYAN}             Tool Verification Report${C_RESET}"
echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"

MISSING=0
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf "  %-15s ${C_GREEN}OK${C_RESET}\n" "$tool"
    else
        printf "  %-15s ${C_RED}MISSING${C_RESET}\n" "$tool"
        MISSING=1
    fi
done
echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"

if [ "$MISSING" -eq 1 ]; then
    echo ""
    log_err "Some tools are still missing."
    log_warn "Open a NEW terminal (to reload PATH) and re-run the script,"
    log_warn "or install the missing tools manually."
    exit 1
fi

log_ok "All required tools installed & verified 🚀"

# ==========================================
# OUTPUT DIRECTORY (named after target)
# ==========================================

mkdir -p "$DOMAIN"
cd "$DOMAIN"

# ==========================================
# SUBDOMAIN ENUMERATION
# ==========================================

echo ""
log_info "Starting Subdomain Enumeration..."

subfinder -d "$DOMAIN" -all -recursive -silent -o subfinder.txt || true
assetfinder --subs-only "$DOMAIN" 2>/dev/null > assetfinder.txt || true

cat subfinder.txt assetfinder.txt 2>/dev/null \
| grep -E "^[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$" \
| sort -u > subs.txt

log_ok "Total Subdomains Found: $(wc -l < subs.txt)"

# ==========================================
# LIVE HOST DETECTION
# ==========================================

echo ""
log_info "Checking Live Hosts..."

httpx -l subs.txt -silent -threads 100 -o live.txt >/dev/null 2>&1 || true

log_ok "Live Hosts Found: $(wc -l < live.txt)"

# ==========================================
# URL COLLECTION
# ==========================================

echo ""
log_info "Collecting URLs..."

touch katana.txt gau.txt wayback.txt

katana -list live.txt -silent -o katana.txt >/dev/null 2>&1 || true
gau --threads 50 < subs.txt > gau.txt 2>/dev/null || true
waybackurls < subs.txt > wayback.txt 2>/dev/null || true

cat katana.txt gau.txt wayback.txt | sort -u > urls.txt

log_ok "Total URLs Collected: $(wc -l < urls.txt)"

# ==========================================
# PARAMETER EXTRACTION
# ==========================================

echo ""
log_info "Extracting Parameters..."

grep "=" urls.txt | sort -u > params.txt || true

log_ok "Parameter URLs Found: $(wc -l < params.txt)"

# ==========================================
# JAVASCRIPT FILES
# ==========================================

echo ""
log_info "Extracting JavaScript Files..."

grep -Ei "\.js(\?|$)" urls.txt | sort -u > js-files.txt || true

log_ok "JavaScript Files Found: $(wc -l < js-files.txt)"

# ==========================================
# SENSITIVE FILES
# ==========================================

echo ""
log_info "Searching For Sensitive Files..."

grep -Ei "\.(env|json|sql|bak|log|yaml|yml|gz|zip|rar|config|xml|txt)(\?|$)" urls.txt \
| sort -u > sensitive-files.txt || true

log_ok "Sensitive Files Found: $(wc -l < sensitive-files.txt)"

# ==========================================
# GF PATTERNS
# ==========================================

echo ""
log_info "Running GF Pattern Matching..."

mkdir -p gf-results

gf xss < urls.txt 2>/dev/null | sort -u > gf-results/xss.txt || true
gf sqli < urls.txt 2>/dev/null | sort -u > gf-results/sqli.txt || true
gf ssrf < urls.txt 2>/dev/null | sort -u > gf-results/ssrf.txt || true
gf lfi < urls.txt 2>/dev/null | sort -u > gf-results/lfi.txt || true
gf redirect < urls.txt 2>/dev/null | sort -u > gf-results/redirect.txt || true

log_ok "GF Pattern Matching Completed"
echo ""
log_ok "XSS Candidates: $(wc -l < gf-results/xss.txt)"
log_ok "SQLi Candidates: $(wc -l < gf-results/sqli.txt)"
log_ok "SSRF Candidates: $(wc -l < gf-results/ssrf.txt)"
log_ok "LFI Candidates: $(wc -l < gf-results/lfi.txt)"
log_ok "Redirect Candidates: $(wc -l < gf-results/redirect.txt)"

# ==========================================
# RECON SUMMARY
# ==========================================

echo ""
echo -e "${C_CYAN}=====================================================${C_RESET}"
echo -e "${C_CYAN}           Adv-Recon Phase Completed 🚀${C_RESET}"
echo -e "${C_CYAN}=====================================================${C_RESET}"
echo ""
echo "Generated Files:"
echo ""
echo "subs.txt                -> All Subdomains"
echo "live.txt                -> Live Hosts"
echo "urls.txt                -> Collected URLs"
echo "params.txt              -> URLs With Parameters"
echo "js-files.txt            -> JavaScript Files"
echo "sensitive-files.txt     -> Sensitive Files"
echo "gf-results/             -> GF Pattern Results"
echo ""

# ==========================================
# ACTIVE VULNERABILITY SCANNER
# ==========================================

mkdir -p scan-results

CURL_OPTS=(-s -k -L --max-time 8 -A "Mozilla/5.0 (Adv-Recon Scanner)")
MAX_PARALLEL=30

# ---------- Detection functions ----------
# Workers run these in subshells, so they rebuild curl opts from CURL_OPTS_STR.

detect_xss () {
    local url="$1" payload="$2"
    local body
    body=$(curl ${CURL_OPTS_STR:-"-s -k -L --max-time 8"} "$url" 2>/dev/null)
    printf '%s' "$body" | grep -qF -- "$payload" && return 0
    return 1
}

detect_sqli () {
    local url="$1" payload="$2"
    local body
    body=$(curl ${CURL_OPTS_STR:-"-s -k -L --max-time 8"} "$url" 2>/dev/null)
    printf '%s' "$body" | grep -qiE \
"you have an error in your sql syntax|warning: mysql|unclosed quotation mark|quoted string not properly terminated|sqlstate|pg_query$$$$|sql syntax.*mariadb|ORA-[0-9]{5}|microsoft ole db provider for sql|psqlexception|sqlite3::|mysql_fetch|mysql_num_rows|supplied argument is not a valid mysql" \
        && return 0
    return 1
}

detect_lfi () {
    local url="$1" payload="$2"
    local body
    body=$(curl ${CURL_OPTS_STR:-"-s -k -L --max-time 8"} "$url" 2>/dev/null)
    printf '%s' "$body" | grep -qiE "root:.*:0:0:|$$boot loader$$|$$fonts$$|; for 16-bit app support|daemon:.*:/usr/sbin" \
        && return 0
    return 1
}

detect_redirect () {
    local url="$1" payload="$2"
    local headers location needle
    headers=$(curl ${CURL_OPTS_STR:-"-s -k -L --max-time 8"} -D - -o /dev/null "$url" 2>/dev/null)
    location=$(printf '%s' "$headers" | grep -i "^location:" | tr -d '\r')
    needle=$(printf '%s' "$payload" | sed -E 's#^https?:/+##I; s#/.*$##')
    [ -n "$needle" ] && printf '%s' "$location" | grep -qiF -- "$needle" && return 0
    return 1
}

detect_ssrf () {
    local url="$1" payload="$2"
    local body
    body=$(curl ${CURL_OPTS_STR:-"-s -k -L --max-time 8"} "$url" 2>/dev/null)
    printf '%s' "$body" | grep -qiE "ami-id|instance-id|iam/security-credentials|computeMetadata|metadata.google.internal" \
        && return 0
    printf '%s' "$body" | grep -qF -- "$payload" && return 0
    return 1
}

# ---------- Progress bar renderer ----------
draw_progress () {
    local current="$1" total="$2" hits="$3" name="$4"
    local width=40
    local percent=0
    [ "$total" -gt 0 ] && percent=$(( current * 100 / total ))
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "\r${C_CYAN}[%s]${C_RESET} [%s] %3d%%  (%d/%d)  ${C_RED}Hits:%d${C_RESET}  " \
        "$name" "$bar" "$percent" "$current" "$total" "$hits"
}

# ---------- Core scan engine (parallel + progress bar) ----------
run_scan () {
    local scan_name="$1"
    local candidate_file="$2"
    local payload_file="$3"
    local detect_func="$4"
    local out_file="$5"

    : > "$out_file"

    if [ ! -s "$candidate_file" ]; then
        log_warn "No candidate URLs found for $scan_name. Skipping."
        return
    fi

    local total_targets total_payloads
    total_targets=$(wc -l < "$candidate_file")
    total_payloads=$(wc -l < "$payload_file")

    echo ""
    log_info "Starting $scan_name scan"
    echo "    Targets : $total_targets"
    echo "    Payloads: $total_payloads"
    echo "    Concurrency: $MAX_PARALLEL"
    echo ""

    # Build injected job list
    local jobfile
    jobfile=$(mktemp)
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        while IFS= read -r payload; do
            [ -z "$payload" ] && continue
            local injected
            injected=$(printf '%s\n' "$url" | qsreplace "$payload" 2>/dev/null)
            [ -z "$injected" ] && continue
            printf '%s\t%s\n' "$injected" "$payload"
        done < "$payload_file"
    done < "$candidate_file" > "$jobfile"

    local real_total
    real_total=$(wc -l < "$jobfile")
    if [ "$real_total" -eq 0 ]; then
        log_warn "No valid injected requests for $scan_name. Skipping."
        rm -f "$jobfile"
        return
    fi

    # Shared progress + hit counters
    local progress_file hit_file lock_file
    progress_file=$(mktemp); hit_file=$(mktemp); lock_file=$(mktemp)
    echo 0 > "$progress_file"; echo 0 > "$hit_file"

    export DETECT_FUNC="$detect_func"
    export OUT_FILE="$out_file"
    export PROGRESS_FILE="$progress_file"
    export HIT_FILE="$hit_file"
    export LOCK_FILE="$lock_file"
    export CURL_OPTS_STR="${CURL_OPTS[*]}"
    export C_RED C_RESET
    export -f "$detect_func"

    # Launch workers
    (
        cat "$jobfile" | xargs -P "$MAX_PARALLEL" -d '\n' -I {} bash -c '
            line="$1"
            url="${line%%	*}"
            payload="${line#*	}"
            if "$DETECT_FUNC" "$url" "$payload"; then
                (
                    flock 9
                    echo "$url" >> "$OUT_FILE"
                    h=$(cat "$HIT_FILE"); echo $((h + 1)) > "$HIT_FILE"
                ) 9>"$LOCK_FILE"
                printf "\r\033[K'"${C_RED}"'[VULN]'"${C_RESET}"' %s\n" "$url"
            fi
            (
                flock 9
                p=$(cat "$PROGRESS_FILE"); echo $((p + 1)) > "$PROGRESS_FILE"
            ) 9>"$LOCK_FILE"
        ' _ {}
    ) &
    local worker_pid=$!

    # Progress bar loop
    while kill -0 "$worker_pid" 2>/dev/null; do
        local cur hits
        cur=$(cat "$progress_file" 2>/dev/null || echo 0)
        hits=$(cat "$hit_file" 2>/dev/null || echo 0)
        draw_progress "$cur" "$real_total" "$hits" "$scan_name"
        sleep 0.3
    done
    wait "$worker_pid" 2>/dev/null || true

    local final_hits
    final_hits=$(cat "$hit_file" 2>/dev/null || echo 0)
    draw_progress "$real_total" "$real_total" "$final_hits" "$scan_name"
    echo ""

    rm -f "$jobfile" "$progress_file" "$hit_file" "$lock_file"

    echo ""
    log_ok "$scan_name scan finished. Confirmed hits: $final_hits"
    log_ok "Results saved to: $DOMAIN/$out_file"
}

# ---------- Scan-ALL helper ----------
declare -A ALL_CAND=(
    [xss]="gf-results/xss.txt" [sqli]="gf-results/sqli.txt" [ssrf]="gf-results/ssrf.txt"
    [lfi]="gf-results/lfi.txt" [redirect]="gf-results/redirect.txt"
)
declare -A ALL_DETECT=(
    [xss]="detect_xss" [sqli]="detect_sqli" [ssrf]="detect_ssrf"
    [lfi]="detect_lfi" [redirect]="detect_redirect"
)
declare -A ALL_OUT=(
    [xss]="scan-results/xss-vuln.txt" [sqli]="scan-results/sqli-vuln.txt"
    [ssrf]="scan-results/ssrf-vuln.txt" [lfi]="scan-results/lfi-vuln.txt"
    [redirect]="scan-results/redirect-vuln.txt"
)

scan_all () {
    local payload_dir="$1" mode="$2"
    local types=(xss sqli ssrf lfi redirect)
    local PIDS=()
    for t in "${types[@]}"; do
        local pfile="$payload_dir/$t.txt"
        if [ ! -s "$pfile" ]; then
            log_warn "No payload file for $t (expected: $pfile). Skipping."
            continue
        fi
        if [ "$mode" = "parallel" ]; then
            run_scan "${t^^}" "${ALL_CAND[$t]}" "$pfile" "${ALL_DETECT[$t]}" "${ALL_OUT[$t]}" &
            PIDS+=("$!")
        else
            run_scan "${t^^}" "${ALL_CAND[$t]}" "$pfile" "${ALL_DETECT[$t]}" "${ALL_OUT[$t]}"
        fi
    done
    if [ "$mode" = "parallel" ]; then
        log_info "All scans launched in parallel. Waiting for completion..."
        for pid in "${PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        log_ok "All parallel scans completed."
    fi
}

# ---------- Interactive menu ----------
while true; do
    echo ""
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "${C_CYAN}        Adv-Recon  ::  Active Scan Menu${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo "  Target: $DOMAIN"
    echo "-----------------------------------------------------"
    echo "  [1] XSS"
    echo "  [2] SQLi"
    echo "  [3] SSRF"
    echo "  [4] LFI"
    echo "  [5] Open Redirect"
    echo "  [6] Scan ALL (sequential or parallel)"
    echo "  [7] Exit"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    read -rp "[?] Select what you want to scan (1-7): " choice

    # --- Scan ALL branch ---
    if [ "$choice" = "6" ]; then
        echo ""
        echo "[i] Scan ALL expects a folder containing payload files named:"
        echo "    xss.txt  sqli.txt  ssrf.txt  lfi.txt  redirect.txt"
        echo "    (Missing files are skipped automatically.)"
        echo ""
        read -rp "[?] Enter full path to your payload FOLDER: " PAYLOAD_DIR

        if [ ! -d "$PAYLOAD_DIR" ]; then
            log_warn "Folder not found: $PAYLOAD_DIR"
            continue
        fi

        echo ""
        echo "  [1] Back-to-back (sequential)  - lighter load, ordered output"
        echo "  [2] Parallel                   - faster, all scans at once"
        read -rp "[?] Choose scan mode (1-2): " mode_choice

        case "$mode_choice" in
            1) SCAN_MODE="sequential" ;;
            2) SCAN_MODE="parallel" ;;
            *) log_warn "Invalid mode. Defaulting to sequential."; SCAN_MODE="sequential" ;;
        esac

        log_info "Running ALL scans in $SCAN_MODE mode..."
        scan_all "$PAYLOAD_DIR" "$SCAN_MODE"

        echo ""
        read -rp "[?] Run another scan? (y/n): " again
        case "$again" in
            y|Y) continue ;;
            *) log_ok "Exiting scanner."; break ;;
        esac
        continue
    fi

    # --- Single-scan branches ---
    case "$choice" in
        1) SCAN_NAME="XSS";      CAND="gf-results/xss.txt";      DETECT="detect_xss";      OUT="scan-results/xss-vuln.txt" ;;
        2) SCAN_NAME="SQLi";     CAND="gf-results/sqli.txt";     DETECT="detect_sqli";     OUT="scan-results/sqli-vuln.txt" ;;
        3) SCAN_NAME="SSRF";     CAND="gf-results/ssrf.txt";     DETECT="detect_ssrf";     OUT="scan-results/ssrf-vuln.txt" ;;
        4) SCAN_NAME="LFI";      CAND="gf-results/lfi.txt";      DETECT="detect_lfi";      OUT="scan-results/lfi-vuln.txt" ;;
        5) SCAN_NAME="Redirect"; CAND="gf-results/redirect.txt"; DETECT="detect_redirect"; OUT="scan-results/redirect-vuln.txt" ;;
        7) log_ok "Exiting scanner."; break ;;
        *) log_warn "Invalid choice. Try again."; continue ;;
    esac

    read -rp "[?] Enter full path to your $SCAN_NAME payload file: " PAYLOAD_FILE

    if [ ! -f "$PAYLOAD_FILE" ]; then
        log_warn "Payload file not found: $PAYLOAD_FILE"
        continue
    fi
    if [ ! -s "$PAYLOAD_FILE" ]; then
        log_warn "Payload file is empty: $PAYLOAD_FILE"
        continue
    fi

    run_scan "$SCAN_NAME" "$CAND" "$PAYLOAD_FILE" "$DETECT" "$OUT"

    echo ""
    read -rp "[?] Run another scan? (y/n): " again
    case "$again" in
        y|Y) continue ;;
        *) log_ok "Exiting scanner."; break ;;
    esac
done

# ==========================================
# FINAL OUTPUT
# ==========================================

echo ""
echo -e "${C_CYAN}=====================================================${C_RESET}"
echo -e "${C_CYAN}           Adv-Recon Completed 🚀${C_RESET}"
echo -e "${C_CYAN}=====================================================${C_RESET}"
echo ""
log_ok "All output stored in folder: $DOMAIN/"
log_ok "Scan results stored in: $DOMAIN/scan-results/"
echo ""
log_ok "Total URLs: $(wc -l < urls.txt)"
log_ok "Total Parameters: $(wc -l < params.txt)"
log_ok "Total JS Files: $(wc -l < js-files.txt)"
log_ok "Total Sensitive Files: $(wc -l < sensitive-files.txt)"
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log_ok "Completed in ${MINUTES}m ${SECONDS}s"
echo ""
log_ok "Happy Hunting 🔥  - Adv-Recon by Pancham Patil & TilakSingh Rana"
echo ""