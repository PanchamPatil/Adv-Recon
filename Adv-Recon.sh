#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

START_TIME=$(date +%s)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# ==========================================
# ADV-RECON :: Advanced Bug Bounty Recon
# ==========================================

C_RESET='\033[0m'; C_GREEN='\033[1;32m'; C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'; C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'

RESULTS_ROOT="${ADV_RECON_RESULTS_DIR:-results}"
MAX_PARALLEL="${ADV_RECON_CONCURRENCY:-30}"
HTTPX_THREADS="${ADV_RECON_HTTPX_THREADS:-100}"
URL_THREADS="${ADV_RECON_URL_THREADS:-50}"
JS_THREADS="${ADV_RECON_JS_THREADS:-20}"
CONNECT_TIMEOUT="${ADV_RECON_CONNECT_TIMEOUT:-5}"
REQUEST_TIMEOUT="${ADV_RECON_TIMEOUT:-10}"
NUCLEI_SEVERITY="${ADV_RECON_NUCLEI_SEVERITY:-low,medium,high,critical}"
USER_AGENT="${ADV_RECON_USER_AGENT:-Mozilla/5.0 (Adv-Recon Scanner)}"
SKIP_INSTALL="${ADV_RECON_SKIP_INSTALL:-0}"
LOG_FILE=""

plain_log () {
    [ -n "$LOG_FILE" ] && printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

log_info () { printf "%b[*]%b %s\n" "$C_BLUE" "$C_RESET" "$1"; plain_log "INFO $1"; }
log_ok ()   { printf "%b[+]%b %s\n" "$C_GREEN" "$C_RESET" "$1"; plain_log "OK $1"; }
log_warn () { printf "%b[!]%b %s\n" "$C_YELLOW" "$C_RESET" "$1"; plain_log "WARN $1"; }
log_err ()  { printf "%b[x]%b %s\n" "$C_RED" "$C_RESET" "$1"; plain_log "ERR $1"; }

usage () {
    cat <<'EOF'
Usage:
  ./Adv-Recon.sh example.com [options]

Options:
  --severity LEVELS    Nuclei severities, comma-separated (default: low,medium,high,critical)
  --threads N          Active scan concurrency (default: 30)
  --timeout N          Per-request timeout in seconds (default: 10)
  --skip-install       Do not install missing dependencies
  -h, --help           Show this help

Environment:
  ADV_RECON_RESULTS_DIR       Output root, relative to the current directory (default: results)
  ADV_RECON_CONCURRENCY       Active scanner concurrency
  ADV_RECON_HTTPX_THREADS     httpx thread count
  ADV_RECON_URL_THREADS       gau thread count
  ADV_RECON_JS_THREADS        JavaScript fetch/analyze concurrency
  ADV_RECON_NUCLEI_SEVERITY   Nuclei severity filter
  ADV_RECON_SKIP_INSTALL=1    Skip dependency installation
EOF
}

banner () {
    cat <<'EOF'
=====================================================
             ADV-RECON
      Advanced Bug Bounty Recon & Scan Framework By Pancham Patil
=====================================================
EOF
}

die () {
    log_err "$1"
    exit 1
}

is_positive_int () {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

normalize_domain_arg () {
    local raw="$1"
    raw="${raw,,}"
    raw="${raw#http://}"
    raw="${raw#https://}"
    raw="${raw%%/*}"
    raw="${raw%%:*}"
    raw="${raw%.}"
    printf '%s' "$raw"
}

validate_domain () {
    local value="$1"
    [[ "$value" != *..* ]] || return 1
    [[ "$value" != -* ]] || return 1
    [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1
    [[ ${#value} -le 253 ]] || return 1
}

validate_results_root () {
    local value="$1"
    [[ -n "$value" ]] || return 1
    [[ "$value" != /* ]] || return 1
    [[ "$value" != *'..'* ]] || return 1
    [[ "$value" != *'~'* ]] || return 1
}

sanitize_name () {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

count_lines () {
    local file="$1"
    [ -s "$file" ] || { printf '0'; return; }
    wc -l < "$file" | tr -d '[:space:]'
}

run_logged () {
    local label="$1"
    shift
    plain_log "CMD $label: $*"
    "$@" >> "$LOG_FILE" 2>&1
}

parse_args () {
    DOMAIN_INPUT=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --severity)
                [ "$#" -ge 2 ] || die "--severity requires a value"
                NUCLEI_SEVERITY="$2"; shift 2 ;;
            --threads)
                [ "$#" -ge 2 ] || die "--threads requires a value"
                is_positive_int "$2" || die "--threads must be a positive integer"
                MAX_PARALLEL="$2"; shift 2 ;;
            --timeout)
                [ "$#" -ge 2 ] || die "--timeout requires a value"
                is_positive_int "$2" || die "--timeout must be a positive integer"
                REQUEST_TIMEOUT="$2"; shift 2 ;;
            --skip-install)
                SKIP_INSTALL=1; shift ;;
            -h|--help)
                usage; exit 0 ;;
            --*)
                die "Unknown option: $1" ;;
            *)
                [ -z "$DOMAIN_INPUT" ] || die "Only one target domain is supported per run"
                DOMAIN_INPUT="$1"; shift ;;
        esac
    done

    [ -n "$DOMAIN_INPUT" ] || { usage; exit 1; }
    DOMAIN="$(normalize_domain_arg "$DOMAIN_INPUT")"
    validate_domain "$DOMAIN" || die "Invalid domain input: $DOMAIN_INPUT"
    validate_results_root "$RESULTS_ROOT" || die "Unsafe ADV_RECON_RESULTS_DIR: $RESULTS_ROOT"
    is_positive_int "$MAX_PARALLEL" || die "ADV_RECON_CONCURRENCY must be a positive integer"
    is_positive_int "$HTTPX_THREADS" || die "ADV_RECON_HTTPX_THREADS must be a positive integer"
    is_positive_int "$URL_THREADS" || die "ADV_RECON_URL_THREADS must be a positive integer"
    is_positive_int "$JS_THREADS" || die "ADV_RECON_JS_THREADS must be a positive integer"
    is_positive_int "$CONNECT_TIMEOUT" || die "ADV_RECON_CONNECT_TIMEOUT must be a positive integer"
    is_positive_int "$REQUEST_TIMEOUT" || die "ADV_RECON_TIMEOUT must be a positive integer"
    [[ "$NUCLEI_SEVERITY" =~ ^(info|low|medium|high|critical)(,(info|low|medium|high|critical))*$ ]] || die "Invalid Nuclei severity list: $NUCLEI_SEVERITY"
    TARGET_SLUG="$(sanitize_name "$DOMAIN")"
}

init_output_tree () {
    OUTPUT_ROOT="$PWD/$RESULTS_ROOT"
    RECON_DIR="$OUTPUT_ROOT/recon"
    URLS_DIR="$OUTPUT_ROOT/urls"
    PORTS_DIR="$OUTPUT_ROOT/ports"
    NUCLEI_DIR="$OUTPUT_ROOT/nuclei"
    SCANS_DIR="$OUTPUT_ROOT/scans"
    REPORTS_DIR="$OUTPUT_ROOT/reports"
    LOGS_DIR="$OUTPUT_ROOT/logs"

    mkdir -p "$RECON_DIR" "$URLS_DIR" "$PORTS_DIR" "$NUCLEI_DIR" "$SCANS_DIR/gf-results" \
        "$SCANS_DIR/active" "$REPORTS_DIR" "$LOGS_DIR"
    LOG_FILE="$LOGS_DIR/adv-recon.log"
    : > "$LOG_FILE"
    printf '%s\n' "$DOMAIN" > "$RECON_DIR/target.txt"
    printf '%s\n' "$TARGET_SLUG" > "$RECON_DIR/target-slug.txt"
}

OS_TYPE="$(uname -s)"
PKG_MANAGER="unknown"
SUDO_CMD=()

detect_pkg_manager () {
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        SUDO_CMD=(sudo)
    fi

    if [ "$OS_TYPE" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"; SUDO_CMD=()
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    fi
}

pkg_update () {
    case "$PKG_MANAGER" in
        apt) "${SUDO_CMD[@]}" apt-get update -y ;;
        dnf) "${SUDO_CMD[@]}" dnf makecache -y ;;
        yum) "${SUDO_CMD[@]}" yum makecache -y ;;
        pacman) "${SUDO_CMD[@]}" pacman -Sy --noconfirm ;;
        zypper) "${SUDO_CMD[@]}" zypper refresh ;;
        apk) "${SUDO_CMD[@]}" apk update ;;
        brew) brew update ;;
        *) return 1 ;;
    esac
}

sys_install () {
    local pkg="$1"
    [ "$PKG_MANAGER" != "unknown" ] || return 1
    case "$PKG_MANAGER" in
        apt) "${SUDO_CMD[@]}" apt-get install -y "$pkg" ;;
        dnf) "${SUDO_CMD[@]}" dnf install -y "$pkg" ;;
        yum) "${SUDO_CMD[@]}" yum install -y "$pkg" ;;
        pacman) "${SUDO_CMD[@]}" pacman -S --noconfirm "$pkg" ;;
        zypper) "${SUDO_CMD[@]}" zypper install -y "$pkg" ;;
        apk) "${SUDO_CMD[@]}" apk add "$pkg" ;;
        brew) brew install "$pkg" ;;
        *) return 1 ;;
    esac
}

ensure_binary () {
    local bin="$1" pkg="${2:-$1}"
    command -v "$bin" >/dev/null 2>&1 && return 0
    [ "$SKIP_INSTALL" = "0" ] || return 1
    log_info "Installing base dependency: $pkg"
    run_logged "install $pkg" sys_install "$pkg" && log_ok "$bin installed" || {
        log_warn "Failed to install $bin"
        return 1
    }
}

install_go_from_tarball () {
    local go_latest goarch goos tarball tmpdir
    go_latest="$(curl -fsSL --retry 3 --connect-timeout 10 'https://go.dev/VERSION?m=text' 2>/dev/null | head -n1 || true)"
    [ -n "$go_latest" ] || go_latest="go1.22.5"
    case "$(uname -m)" in
        x86_64|amd64) goarch="amd64" ;;
        aarch64|arm64) goarch="arm64" ;;
        i386|i686) goarch="386" ;;
        *) goarch="amd64" ;;
    esac
    [ "$OS_TYPE" = "Darwin" ] && goos="darwin" || goos="linux"
    tarball="${go_latest}.${goos}-${goarch}.tar.gz"
    tmpdir="$(mktemp -d)"

    log_info "Downloading $tarball"
    if curl -fsSL --retry 3 --connect-timeout 10 "https://go.dev/dl/${tarball}" -o "$tmpdir/go.tar.gz"; then
        if [ "$(id -u)" -eq 0 ] || [ "${#SUDO_CMD[@]}" -gt 0 ]; then
            "${SUDO_CMD[@]}" rm -rf /usr/local/go
            "${SUDO_CMD[@]}" tar -C /usr/local -xzf "$tmpdir/go.tar.gz"
            log_ok "Go $go_latest installed"
        else
            log_warn "Go download succeeded, but root/sudo is required to install under /usr/local"
        fi
    else
        log_warn "Failed to download Go tarball"
    fi
    rm -rf "$tmpdir"
}

ensure_go () {
    command -v go >/dev/null 2>&1 && {
        log_ok "Go already installed: $(go version | awk '{print $3}')"
        return 0
    }

    [ "$SKIP_INSTALL" = "0" ] || return 1
    log_info "Go not found. Trying package manager first."
    sys_install golang-go >> "$LOG_FILE" 2>&1 || sys_install go >> "$LOG_FILE" 2>&1 || install_go_from_tarball
    command -v go >/dev/null 2>&1
}

persist_path () {
    local rcfile="$HOME/.bashrc"
    [ -n "${ZSH_VERSION:-}" ] && rcfile="$HOME/.zshrc"
    [ -f "$rcfile" ] || touch "$rcfile" 2>/dev/null || return 0
    if ! grep -q "Added by Adv-Recon" "$rcfile" 2>/dev/null; then
        {
            echo ""
            echo "# Added by Adv-Recon"
            echo "export PATH=\$PATH:/usr/local/go/bin"
            echo "export GOPATH=\${GOPATH:-\$HOME/go}"
            echo "export PATH=\$PATH:\$GOPATH/bin"
        } >> "$rcfile"
        log_ok "PATH persisted to $rcfile"
    fi
}

declare -A GO_TOOLS=(
    [subfinder]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [katana]="github.com/projectdiscovery/katana/cmd/katana@latest"
    [dnsx]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    [naabu]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    [nuclei]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    [assetfinder]="github.com/tomnomnom/assetfinder@latest"
    [gau]="github.com/lc/gau/v2/cmd/gau@latest"
    [waybackurls]="github.com/tomnomnom/waybackurls@latest"
    [qsreplace]="github.com/tomnomnom/qsreplace@latest"
    [gf]="github.com/tomnomnom/gf@latest"
)

REQUIRED_TOOLS=(curl git tar unzip flock subfinder httpx katana dnsx naabu nuclei assetfinder gau waybackurls qsreplace gf)
OPTIONAL_TOOLS=(amass findomain jq)

install_go_tool () {
    local name="$1" path="$2"
    command -v "$name" >/dev/null 2>&1 && return 0
    log_info "Installing Go tool: $name"
    if go install -v "$path" >> "$LOG_FILE" 2>&1; then
        log_ok "Installed: $name"
        return 0
    fi
    log_warn "Failed to install: $name"
    return 1
}

setup_gf_patterns () {
    command -v gf >/dev/null 2>&1 || return 0
    log_info "Setting up gf patterns"
    mkdir -p "$HOME/.gf"
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone -q https://github.com/tomnomnom/gf "$tmpdir/gf" >> "$LOG_FILE" 2>&1 || true
    cp -r "$tmpdir/gf/examples/." "$HOME/.gf/" 2>/dev/null || true
    git clone -q https://github.com/1ndianl33t/Gf-Patterns "$tmpdir/gf-patterns" >> "$LOG_FILE" 2>&1 || true
    cp -r "$tmpdir/gf-patterns/"*.json "$HOME/.gf/" 2>/dev/null || true
    rm -rf "$tmpdir"
    log_ok "gf patterns ready ($(find "$HOME/.gf" -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]') patterns)"
}

install_dependencies () {
    detect_pkg_manager
    log_info "OS detected      : $OS_TYPE"
    log_info "Package manager  : $PKG_MANAGER"
    log_info "Architecture     : $(uname -m)"

    if [ "$SKIP_INSTALL" = "1" ]; then
        log_warn "Dependency installation skipped"
    else
        [ "$PKG_MANAGER" = "unknown" ] && log_warn "Unknown package manager. Base packages must be installed manually."
        [ "$PKG_MANAGER" != "unknown" ] && run_logged "package update" pkg_update || true

        ensure_binary curl curl || true
        ensure_binary git git || true
        ensure_binary tar tar || true
        ensure_binary unzip unzip || true
        ensure_binary flock util-linux || true
        [ "$PKG_MANAGER" = "apt" ] && sys_install ca-certificates >> "$LOG_FILE" 2>&1 || true
        [ "$PKG_MANAGER" = "apt" ] && sys_install libpcap-dev >> "$LOG_FILE" 2>&1 || true

        ensure_go || log_warn "Go is still missing; Go-based tools may not install"
        export PATH="$PATH:/usr/local/go/bin"
        export GOPATH="${GOPATH:-$HOME/go}"
        export GOBIN="${GOBIN:-$GOPATH/bin}"
        mkdir -p "$GOBIN"
        export PATH="$PATH:$GOBIN"
        persist_path

        if command -v go >/dev/null 2>&1; then
            for name in "${!GO_TOOLS[@]}"; do
                install_go_tool "$name" "${GO_TOOLS[$name]}" || true
            done
        fi

        ensure_binary amass amass || log_warn "Amass is optional and was not installed"
        ensure_binary findomain findomain || log_warn "Findomain is optional and was not installed"
        ensure_binary jq jq || true
        setup_gf_patterns
    fi

    verify_tools
}

verify_tools () {
    local missing=0
    echo ""
    echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"
    echo -e "${C_CYAN}             Tool Verification Report${C_RESET}"
    echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf "  %-15s ${C_GREEN}OK${C_RESET}\n" "$tool"
        else
            printf "  %-15s ${C_RED}MISSING${C_RESET}\n" "$tool"
            missing=1
        fi
    done
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf "  %-15s ${C_GREEN}OK${C_RESET} (optional)\n" "$tool"
        else
            printf "  %-15s ${C_YELLOW}MISSING${C_RESET} (optional)\n" "$tool"
        fi
    done
    echo -e "${C_CYAN}-----------------------------------------------------${C_RESET}"
    [ "$missing" -eq 0 ] || die "Required tools are missing. Re-run without --skip-install or install them manually."
}

domain_regex () {
    printf '%s' "$DOMAIN" | sed 's/\./\\./g'
}

normalize_subdomains () {
    awk '{ gsub(/\r/,""); sub(/^\*\./,""); sub(/\.$/,""); print tolower($0) }' |
        grep -E "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]*[a-z0-9]$" |
        grep -E "(^|\.)$(domain_regex)$" |
        LC_ALL=C sort -u
}

normalize_urls () {
    awk '{ gsub(/\r/,""); print }' |
        grep -E '^https?://[^[:space:]]+$' |
        LC_ALL=C sort -u
}

run_recon () {
    log_info "Starting subdomain enumeration"
    : > "$RECON_DIR/subfinder.txt"
    : > "$RECON_DIR/assetfinder.txt"
    : > "$RECON_DIR/amass.txt"
    : > "$RECON_DIR/findomain.txt"

    subfinder -d "$DOMAIN" -all -recursive -silent -o "$RECON_DIR/subfinder.txt" >> "$LOG_FILE" 2>&1 || true
    assetfinder --subs-only "$DOMAIN" > "$RECON_DIR/assetfinder.txt" 2>> "$LOG_FILE" || true

    if command -v amass >/dev/null 2>&1; then
        amass enum -passive -d "$DOMAIN" -o "$RECON_DIR/amass.txt" >> "$LOG_FILE" 2>&1 || true
    else
        log_warn "Amass not found; skipping Amass enumeration"
    fi

    if command -v findomain >/dev/null 2>&1; then
        findomain -t "$DOMAIN" -q > "$RECON_DIR/findomain.txt" 2>> "$LOG_FILE" || true
    else
        log_warn "Findomain not found; skipping Findomain enumeration"
    fi

    cat "$RECON_DIR/subfinder.txt" "$RECON_DIR/assetfinder.txt" "$RECON_DIR/amass.txt" "$RECON_DIR/findomain.txt" 2>/dev/null |
        normalize_subdomains > "$RECON_DIR/subs.txt"

    log_ok "Total unique subdomains: $(count_lines "$RECON_DIR/subs.txt")"

    log_info "Resolving subdomains with dnsx"
    if [ -s "$RECON_DIR/subs.txt" ]; then
        dnsx -l "$RECON_DIR/subs.txt" -silent -retry 2 -o "$RECON_DIR/dnsx.txt" >> "$LOG_FILE" 2>&1 || true
        normalize_subdomains < "$RECON_DIR/dnsx.txt" > "$RECON_DIR/resolved.txt" || true
    else
        : > "$RECON_DIR/dnsx.txt"; : > "$RECON_DIR/resolved.txt"
    fi
    log_ok "Resolved subdomains: $(count_lines "$RECON_DIR/resolved.txt")"
}

run_live_discovery () {
    local input_file="$RECON_DIR/resolved.txt"
    [ -s "$input_file" ] || input_file="$RECON_DIR/subs.txt"
    : > "$RECON_DIR/live.txt"
    : > "$RECON_DIR/live.jsonl"
    : > "$RECON_DIR/live-hosts.txt"

    [ -s "$input_file" ] || {
        log_warn "No subdomains available for live host discovery"
        return
    }

    log_info "Checking live hosts with httpx"
    httpx -l "$input_file" -silent -threads "$HTTPX_THREADS" -timeout "$REQUEST_TIMEOUT" -retries 1 \
        -sc -title -td -server -cl -fhr \
        -o "$RECON_DIR/live.txt" >> "$LOG_FILE" 2>&1 || true

    httpx -l "$input_file" -silent -threads "$HTTPX_THREADS" -timeout "$REQUEST_TIMEOUT" -retries 1 \
        -sc -title -td -server -cl -fhr -json \
        -o "$RECON_DIR/live.jsonl" >> "$LOG_FILE" 2>&1 || true

    awk '{print $1}' "$RECON_DIR/live.txt" | grep -E '^https?://' | LC_ALL=C sort -u > "$RECON_DIR/live-hosts.txt" || true
    log_ok "Live hosts found: $(count_lines "$RECON_DIR/live-hosts.txt")"
}

run_port_scan () {
    local input_file="$RECON_DIR/resolved.txt"
    [ -s "$input_file" ] || input_file="$RECON_DIR/subs.txt"
    : > "$PORTS_DIR/ports.txt"

    [ -s "$input_file" ] || {
        log_warn "No hosts available for Naabu port scan"
        return
    }

    log_info "Running Naabu port scan"
    naabu -list "$input_file" -silent -top-ports 1000 -rate "${ADV_RECON_NAABU_RATE:-1000}" \
        -o "$PORTS_DIR/ports.txt" >> "$LOG_FILE" 2>&1 || true
    log_ok "Open ports found: $(count_lines "$PORTS_DIR/ports.txt")"
}

run_url_collection () {
    log_info "Collecting URLs"
    : > "$URLS_DIR/katana.txt"
    : > "$URLS_DIR/gau.txt"
    : > "$URLS_DIR/wayback.txt"
    : > "$URLS_DIR/urls.txt"

    if [ -s "$RECON_DIR/live-hosts.txt" ]; then
        katana -list "$RECON_DIR/live-hosts.txt" -silent -o "$URLS_DIR/katana.txt" >> "$LOG_FILE" 2>&1 || true
    fi

    if [ -s "$RECON_DIR/subs.txt" ]; then
        gau --threads "$URL_THREADS" < "$RECON_DIR/subs.txt" > "$URLS_DIR/gau.txt" 2>> "$LOG_FILE" || true
        waybackurls < "$RECON_DIR/subs.txt" > "$URLS_DIR/wayback.txt" 2>> "$LOG_FILE" || true
    fi

    cat "$URLS_DIR/katana.txt" "$URLS_DIR/gau.txt" "$URLS_DIR/wayback.txt" 2>/dev/null |
        normalize_urls > "$URLS_DIR/urls.txt"

    grep -E '[?&][^=]+=.*' "$URLS_DIR/urls.txt" | LC_ALL=C sort -u > "$URLS_DIR/params.txt" || true
    grep -Ei '\.js([?#]|$)' "$URLS_DIR/urls.txt" | LC_ALL=C sort -u > "$URLS_DIR/js-files.txt" || true
    grep -Ei '\.(env|json|sql|bak|backup|log|yaml|yml|gz|zip|rar|config|conf|xml|txt)([?#]|$)' "$URLS_DIR/urls.txt" |
        LC_ALL=C sort -u > "$URLS_DIR/sensitive-files.txt" || true

    log_ok "Total URLs collected: $(count_lines "$URLS_DIR/urls.txt")"
    log_ok "Parameter URLs found: $(count_lines "$URLS_DIR/params.txt")"
    log_ok "JavaScript files found: $(count_lines "$URLS_DIR/js-files.txt")"
    log_ok "Sensitive files found: $(count_lines "$URLS_DIR/sensitive-files.txt")"
}

run_gf_matching () {
    log_info "Running gf pattern matching"
    mkdir -p "$SCANS_DIR/gf-results"
    : > "$SCANS_DIR/gf-results/xss.txt"
    : > "$SCANS_DIR/gf-results/sqli.txt"
    : > "$SCANS_DIR/gf-results/ssrf.txt"
    : > "$SCANS_DIR/gf-results/lfi.txt"
    : > "$SCANS_DIR/gf-results/redirect.txt"

    [ -s "$URLS_DIR/urls.txt" ] || {
        log_warn "No URLs available for gf matching"
        return
    }

    gf xss < "$URLS_DIR/urls.txt" 2>> "$LOG_FILE" | LC_ALL=C sort -u > "$SCANS_DIR/gf-results/xss.txt" || true
    gf sqli < "$URLS_DIR/urls.txt" 2>> "$LOG_FILE" | LC_ALL=C sort -u > "$SCANS_DIR/gf-results/sqli.txt" || true
    gf ssrf < "$URLS_DIR/urls.txt" 2>> "$LOG_FILE" | LC_ALL=C sort -u > "$SCANS_DIR/gf-results/ssrf.txt" || true
    gf lfi < "$URLS_DIR/urls.txt" 2>> "$LOG_FILE" | LC_ALL=C sort -u > "$SCANS_DIR/gf-results/lfi.txt" || true
    gf redirect < "$URLS_DIR/urls.txt" 2>> "$LOG_FILE" | LC_ALL=C sort -u > "$SCANS_DIR/gf-results/redirect.txt" || true

    log_ok "XSS candidates: $(count_lines "$SCANS_DIR/gf-results/xss.txt")"
    log_ok "SQLi candidates: $(count_lines "$SCANS_DIR/gf-results/sqli.txt")"
    log_ok "SSRF candidates: $(count_lines "$SCANS_DIR/gf-results/ssrf.txt")"
    log_ok "LFI candidates: $(count_lines "$SCANS_DIR/gf-results/lfi.txt")"
    log_ok "Redirect candidates: $(count_lines "$SCANS_DIR/gf-results/redirect.txt")"
}

redact_match () {
    sed -E 's/([A-Za-z0-9_=-]{6})[A-Za-z0-9_+=\/.-]{8,}([A-Za-z0-9_=-]{4})/\1...\2/g'
}

analyze_one_js () {
    local url="$1" body
    body="$(curl -sS -k -L --max-time "$REQUEST_TIMEOUT" --connect-timeout "$CONNECT_TIMEOUT" -A "$USER_AGENT" "$url" 2>/dev/null || true)"
    [ -n "$body" ] || return 0

    printf '%s' "$body" | grep -Eao 'AKIA[0-9A-Z]{16}' | head -n 10 | redact_match | awk -v u="$url" '{print "aws_access_key\t" u "\t" $0}'
    printf '%s' "$body" | grep -Eao 'AIza[0-9A-Za-z_-]{30,45}' | head -n 10 | redact_match | awk -v u="$url" '{print "google_api_key\t" u "\t" $0}'
    printf '%s' "$body" | grep -Eao 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' | head -n 10 | redact_match | awk -v u="$url" '{print "jwt\t" u "\t" $0}'
    printf '%s' "$body" | grep -Eaio '(api[_-]?key|client[_-]?secret|secret|token)["'\''[:space:]]*[:=]["'\''[:space:]]*[A-Za-z0-9_./+=:-]{12,}' | head -n 20 | redact_match | awk -v u="$url" '{print "generic_secret\t" u "\t" $0}'
    printf '%s' "$body" | grep -Eaio '(firebaseConfig|firebaseio\.com|authDomain|projectId|storageBucket)' | head -n 10 | awk -v u="$url" '{print "firebase_config\t" u "\t" $0}'
    printf '%s' "$body" | grep -Eaio '(/graphql|graphqlEndpoint|graphql_url|hasura|apollo)' | head -n 10 | awk -v u="$url" '{print "graphql_indicator\t" u "\t" $0}'
    return 0
}
export -f analyze_one_js redact_match

run_js_analysis () {
    log_info "Analyzing JavaScript for secrets and endpoints"
    : > "$URLS_DIR/js-findings.tsv"
    [ -s "$URLS_DIR/js-files.txt" ] || {
        log_warn "No JavaScript URLs found"
        return
    }

    export REQUEST_TIMEOUT CONNECT_TIMEOUT USER_AGENT
    xargs -P "$JS_THREADS" -n 1 bash -c 'analyze_one_js "$1"' _ < "$URLS_DIR/js-files.txt" |
        LC_ALL=C sort -u > "$URLS_DIR/js-findings.tsv" || true

    log_ok "JavaScript findings: $(count_lines "$URLS_DIR/js-findings.tsv")"
}

run_nuclei () {
    log_info "Running Nuclei vulnerability discovery"
    : > "$NUCLEI_DIR/nuclei.jsonl"
    : > "$NUCLEI_DIR/nuclei.txt"
    [ -s "$RECON_DIR/live-hosts.txt" ] || {
        log_warn "No live hosts available for Nuclei"
        return
    }

    nuclei -update-templates -silent >> "$LOG_FILE" 2>&1 || true
    nuclei -l "$RECON_DIR/live-hosts.txt" -severity "$NUCLEI_SEVERITY" -jsonl \
        -o "$NUCLEI_DIR/nuclei.jsonl" >> "$LOG_FILE" 2>&1 || true

    if command -v jq >/dev/null 2>&1 && [ -s "$NUCLEI_DIR/nuclei.jsonl" ]; then
        jq -r '[.info.severity, (."template-id" // .templateID), (.matched-at // .matched), .info.name] | @tsv' "$NUCLEI_DIR/nuclei.jsonl" > "$NUCLEI_DIR/nuclei.txt" 2>> "$LOG_FILE" || true
    elif [ -s "$NUCLEI_DIR/nuclei.jsonl" ]; then
        sed -E 's/.*"severity":"?([^",}]+)"?.*"template-id":"?([^",}]+)"?.*/\1\t\2/' "$NUCLEI_DIR/nuclei.jsonl" > "$NUCLEI_DIR/nuclei.txt" || true
    fi

    for sev in info low medium high critical unknown; do
        grep -Ei "\"severity\"[[:space:]]*:[[:space:]]*\"$sev\"" "$NUCLEI_DIR/nuclei.jsonl" > "$NUCLEI_DIR/nuclei-${sev}.jsonl" || true
    done

    log_ok "Nuclei findings: $(count_lines "$NUCLEI_DIR/nuclei.jsonl")"
}

fetch_body () {
    curl -sS -k -L --max-time "$REQUEST_TIMEOUT" --connect-timeout "$CONNECT_TIMEOUT" -A "$USER_AGENT" "$1" 2>/dev/null || true
}

fetch_headers_no_follow () {
    curl -sS -k -I --max-time "$REQUEST_TIMEOUT" --connect-timeout "$CONNECT_TIMEOUT" -A "$USER_AGENT" "$1" 2>/dev/null || true
}

url_host () {
    printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+).*#\1#' | tr '[:upper:]' '[:lower:]'
}

detect_xss () {
    local url="$1" payload="$2" body
    body="$(fetch_body "$url")"
    [ -n "$body" ] || return 1
    printf '%s' "$body" | grep -qF -- "$payload"
}

detect_sqli () {
    local url="$1" payload="$2" body
    body="$(fetch_body "$url")"
    [ -n "$body" ] || return 1
    printf '%s' "$body" | grep -qiE 'you have an error in your sql syntax|warning: mysql|unclosed quotation mark|quoted string not properly terminated|sqlstate|pg_query\(|sql syntax.*mariadb|ORA-[0-9]{5}|microsoft ole db provider for sql|psqlexception|sqlite3::|mysql_fetch|mysql_num_rows|supplied argument is not a valid mysql|syntax error at or near|unterminated quoted string'
}

detect_lfi () {
    local url="$1" payload="$2" body
    body="$(fetch_body "$url")"
    [ -n "$body" ] || return 1
    printf '%s' "$body" | grep -qiE 'root:.*:0:0:|daemon:.*:/usr/sbin|for 16-bit app support|\[boot loader\]|\[fonts\]'
}

detect_redirect () {
    local url="$1" payload="$2" headers location payload_host original_host
    payload_host="$(url_host "$payload")"
    original_host="$(url_host "$url")"
    [ -n "$payload_host" ] && [ "$payload_host" != "$original_host" ] || return 1
    headers="$(fetch_headers_no_follow "$url")"
    location="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/\r$/,""); sub(/^[Ll]ocation:[[:space:]]*/,""); print; exit}')"
    [ -n "$location" ] || return 1
    printf '%s' "$location" | grep -qiF -- "$payload_host"
}

detect_ssrf () {
    local url="$1" payload="$2" body
    body="$(fetch_body "$url")"
    [ -n "$body" ] || return 1
    printf '%s' "$body" | grep -qiE 'ami-id|instance-id|iam/security-credentials|metadata.google.internal|computeMetadata|azure-instance-metadata|ec2metadata'
}

draw_progress () {
    local current="$1" total="$2" hits="$3" name="$4"
    local width=32 percent=0 filled empty bar="" i
    [ "$total" -gt 0 ] && percent=$(( current * 100 / total ))
    [ "$percent" -gt 100 ] && percent=100
    filled=$(( percent * width / 100 ))
    empty=$(( width - filled ))
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="."; done
    printf "\r${C_CYAN}[%s]${C_RESET} [%s] %3d%% (%d/%d) ${C_RED}Hits:%d${C_RESET}  " \
        "$name" "$bar" "$percent" "$current" "$total" "$hits"
}

generate_scan_jobs () {
    local candidate_file="$1" payload_file="$2"
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        [[ "$url" =~ ^https?:// ]] || continue
        while IFS= read -r payload; do
            [ -n "$payload" ] || continue
            printf '%s\n' "$url" | qsreplace "$payload" 2>/dev/null |
                awk -v p="$payload" 'NF { print $0 "\t" p }'
        done < "$payload_file"
    done < "$candidate_file"
}

run_scan () {
    local scan_name="$1" candidate_file="$2" payload_file="$3" detect_func="$4" out_file="$5"
    : > "$out_file"

    [ -s "$candidate_file" ] || {
        log_warn "No candidate URLs found for $scan_name. Skipping."
        return
    }
    [ -s "$payload_file" ] || {
        log_warn "Payload file is empty for $scan_name. Skipping."
        return
    }

    local total_targets total_payloads real_total progress_file hit_file lock_file worker_pid final_hits
    total_targets=$(count_lines "$candidate_file")
    total_payloads=$(count_lines "$payload_file")
    real_total=$(( total_targets * total_payloads ))

    echo ""
    log_info "Starting $scan_name scan"
    echo "    Targets    : $total_targets"
    echo "    Payloads   : $total_payloads"
    echo "    Concurrency: $MAX_PARALLEL"
    echo "    Timeout    : ${REQUEST_TIMEOUT}s"
    echo ""

    progress_file="$(mktemp)"
    hit_file="$(mktemp)"
    lock_file="$(mktemp)"
    echo 0 > "$progress_file"
    echo 0 > "$hit_file"

    export DETECT_FUNC="$detect_func" OUT_FILE="$out_file" PROGRESS_FILE="$progress_file"
    export HIT_FILE="$hit_file" LOCK_FILE="$lock_file" REQUEST_TIMEOUT CONNECT_TIMEOUT USER_AGENT C_RED C_RESET
    export -f "$detect_func" fetch_body fetch_headers_no_follow url_host

    (
        generate_scan_jobs "$candidate_file" "$payload_file" |
            xargs -r -P "$MAX_PARALLEL" -d '\n' -I {} bash -c '
                line="$1"
                url="${line%%	*}"
                payload="${line#*	}"
                if "$DETECT_FUNC" "$url" "$payload"; then
                    (
                        flock 9
                        printf "%s\n" "$url" >> "$OUT_FILE"
                        h=$(cat "$HIT_FILE"); echo $((h + 1)) > "$HIT_FILE"
                    ) 9>"$LOCK_FILE"
                    printf "\r\033[K'"${C_RED}"'[POTENTIAL]'"${C_RESET}"' %s\n" "$url"
                fi
                (
                    flock 9
                    p=$(cat "$PROGRESS_FILE"); echo $((p + 1)) > "$PROGRESS_FILE"
                ) 9>"$LOCK_FILE"
            ' _ {}
    ) &
    worker_pid=$!

    while kill -0 "$worker_pid" 2>/dev/null; do
        draw_progress "$(cat "$progress_file" 2>/dev/null || echo 0)" "$real_total" "$(cat "$hit_file" 2>/dev/null || echo 0)" "$scan_name"
        sleep 0.3
    done
    wait "$worker_pid" 2>/dev/null || true

    final_hits="$(cat "$hit_file" 2>/dev/null || echo 0)"
    draw_progress "$real_total" "$real_total" "$final_hits" "$scan_name"
    echo ""

    LC_ALL=C sort -u "$out_file" -o "$out_file" 2>/dev/null || true
    rm -f "$progress_file" "$hit_file" "$lock_file"
    log_ok "$scan_name scan finished. Potential hits: $(count_lines "$out_file")"
    log_ok "Results saved to: $out_file"
}

declare -A ALL_CAND=()
declare -A ALL_DETECT=(
    [xss]="detect_xss" [sqli]="detect_sqli" [ssrf]="detect_ssrf"
    [lfi]="detect_lfi" [redirect]="detect_redirect"
)
declare -A ALL_OUT=()

refresh_scan_maps () {
    ALL_CAND[xss]="$SCANS_DIR/gf-results/xss.txt"; ALL_CAND[sqli]="$SCANS_DIR/gf-results/sqli.txt"
    ALL_CAND[ssrf]="$SCANS_DIR/gf-results/ssrf.txt"; ALL_CAND[lfi]="$SCANS_DIR/gf-results/lfi.txt"
    ALL_CAND[redirect]="$SCANS_DIR/gf-results/redirect.txt"
    ALL_OUT[xss]="$SCANS_DIR/active/xss-potential.txt"; ALL_OUT[sqli]="$SCANS_DIR/active/sqli-potential.txt"
    ALL_OUT[ssrf]="$SCANS_DIR/active/ssrf-potential.txt"; ALL_OUT[lfi]="$SCANS_DIR/active/lfi-potential.txt"
    ALL_OUT[redirect]="$SCANS_DIR/active/redirect-potential.txt"
}

scan_all () {
    local payload_dir="$1" mode="$2" t pfile pid
    local types=(xss sqli ssrf lfi redirect)
    local pids=()
    refresh_scan_maps
    for t in "${types[@]}"; do
        pfile="$payload_dir/$t.txt"
        [ -s "$pfile" ] || {
            log_warn "No payload file for $t (expected: $pfile). Skipping."
            continue
        }
        if [ "$mode" = "parallel" ]; then
            run_scan "${t^^}" "${ALL_CAND[$t]}" "$pfile" "${ALL_DETECT[$t]}" "${ALL_OUT[$t]}" &
            pids+=("$!")
        else
            run_scan "${t^^}" "${ALL_CAND[$t]}" "$pfile" "${ALL_DETECT[$t]}" "${ALL_OUT[$t]}"
        fi
    done
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

active_scan_menu () {
    refresh_scan_maps
    while true; do
        echo ""
        echo -e "${C_CYAN}=====================================================${C_RESET}"
        echo -e "${C_CYAN}        Adv-Recon :: Active Scan Menu${C_RESET}"
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

        if [ "$choice" = "6" ]; then
            read -rp "[?] Enter full path to your payload FOLDER: " payload_dir
            [ -d "$payload_dir" ] || { log_warn "Folder not found: $payload_dir"; continue; }
            echo "  [1] Sequential"
            echo "  [2] Parallel"
            read -rp "[?] Choose scan mode (1-2): " mode_choice
            [ "$mode_choice" = "2" ] && scan_mode="parallel" || scan_mode="sequential"
            scan_all "$payload_dir" "$scan_mode"
            read -rp "[?] Run another scan? (y/n): " again
            [[ "$again" =~ ^[Yy]$ ]] && continue || break
        fi

        case "$choice" in
            1) scan_name="XSS"; key="xss" ;;
            2) scan_name="SQLi"; key="sqli" ;;
            3) scan_name="SSRF"; key="ssrf" ;;
            4) scan_name="LFI"; key="lfi" ;;
            5) scan_name="Redirect"; key="redirect" ;;
            7) log_ok "Exiting scanner."; break ;;
            *) log_warn "Invalid choice. Try again."; continue ;;
        esac

        read -rp "[?] Enter full path to your $scan_name payload file: " payload_file
        [ -f "$payload_file" ] || { log_warn "Payload file not found: $payload_file"; continue; }
        [ -s "$payload_file" ] || { log_warn "Payload file is empty: $payload_file"; continue; }
        run_scan "$scan_name" "${ALL_CAND[$key]}" "$payload_file" "${ALL_DETECT[$key]}" "${ALL_OUT[$key]}"
        read -rp "[?] Run another scan? (y/n): " again
        [[ "$again" =~ ^[Yy]$ ]] && continue || break
    done
}

html_escape () {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

generate_reports () {
    local md="$REPORTS_DIR/report.md" html="$REPORTS_DIR/report.html"
    local end_time duration minutes seconds
    end_time=$(date +%s)
    duration=$((end_time - START_TIME))
    minutes=$((duration / 60))
    seconds=$((duration % 60))

    cat > "$md" <<EOF
# Adv-Recon Report: $DOMAIN

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

## Summary

| Metric | Count |
| --- | ---: |
| Subdomains | $(count_lines "$RECON_DIR/subs.txt") |
| Resolved subdomains | $(count_lines "$RECON_DIR/resolved.txt") |
| Live hosts | $(count_lines "$RECON_DIR/live-hosts.txt") |
| URLs | $(count_lines "$URLS_DIR/urls.txt") |
| Parameter URLs | $(count_lines "$URLS_DIR/params.txt") |
| JavaScript files | $(count_lines "$URLS_DIR/js-files.txt") |
| JavaScript findings | $(count_lines "$URLS_DIR/js-findings.tsv") |
| Sensitive file URLs | $(count_lines "$URLS_DIR/sensitive-files.txt") |
| Open ports | $(count_lines "$PORTS_DIR/ports.txt") |
| Nuclei findings | $(count_lines "$NUCLEI_DIR/nuclei.jsonl") |
| XSS candidates | $(count_lines "$SCANS_DIR/gf-results/xss.txt") |
| SQLi candidates | $(count_lines "$SCANS_DIR/gf-results/sqli.txt") |
| SSRF candidates | $(count_lines "$SCANS_DIR/gf-results/ssrf.txt") |
| LFI candidates | $(count_lines "$SCANS_DIR/gf-results/lfi.txt") |
| Redirect candidates | $(count_lines "$SCANS_DIR/gf-results/redirect.txt") |

## Key Files

- Recon: \`$RECON_DIR\`
- URLs: \`$URLS_DIR\`
- Ports: \`$PORTS_DIR/ports.txt\`
- Nuclei: \`$NUCLEI_DIR\`
- Active scans: \`$SCANS_DIR/active\`
- Logs: \`$LOG_FILE\`

## Runtime

Completed in ${minutes}m ${seconds}s.
EOF

    {
        echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
        echo "<title>Adv-Recon Report - $(printf '%s' "$DOMAIN" | html_escape)</title>"
        echo '<style>body{font-family:Arial,sans-serif;margin:2rem;line-height:1.45;color:#111}table{border-collapse:collapse;width:100%;max-width:760px}td,th{border:1px solid #ddd;padding:.55rem;text-align:left}th{background:#f4f4f4}.path{font-family:monospace;background:#f6f6f6;padding:.15rem .3rem}</style>'
        echo '</head><body>'
        sed -n '1,120p' "$md" | html_escape | awk '
            /^# / {sub(/^# /,""); print "<h1>" $0 "</h1>"; next}
            /^## / {sub(/^## /,""); print "<h2>" $0 "</h2>"; next}
            /^\| Metric/ {in_table=1; print "<table><tr><th>Metric</th><th>Count</th></tr>"; next}
            /^\| ---/ {next}
            in_table && /^\|/ {gsub(/^\| |\|$/,""); split($0,a," | "); print "<tr><td>" a[1] "</td><td>" a[2] "</td></tr>"; next}
            in_table && !/^\|/ {print "</table>"; in_table=0}
            /^- / {sub(/^- /,""); gsub(/`/,""); print "<p class=\"path\">" $0 "</p>"; next}
            NF {print "<p>" $0 "</p>"}
            END {if(in_table) print "</table>"}
        '
        echo '</body></html>'
    } > "$html"

    log_ok "Markdown report saved to: $md"
    log_ok "HTML report saved to: $html"
}

main () {
    banner
    parse_args "$@"
    init_output_tree

    echo ""
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "${C_CYAN}        Adv-Recon :: Dependency Installer${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    install_dependencies

    run_recon
    run_live_discovery
    run_port_scan
    run_url_collection
    run_gf_matching
    run_js_analysis
    run_nuclei

    echo ""
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "${C_CYAN}        Adv-Recon Recon Phase Completed${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo "Output root: $OUTPUT_ROOT"
    echo "Reports    : $REPORTS_DIR"
    echo ""

    active_scan_menu
    generate_reports

    echo ""
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    echo -e "${C_CYAN}        Adv-Recon Completed${C_RESET}"
    echo -e "${C_CYAN}=====================================================${C_RESET}"
    log_ok "All output stored in: $OUTPUT_ROOT"
    log_ok "Happy hunting - use only on authorized targets."
}

main "$@"
