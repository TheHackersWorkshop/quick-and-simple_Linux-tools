#!/bin/bash

# System Diagnostic Report Generator - Bulletproof Edition
set -euo pipefail
shopt -s nullglob

# --- TRAP HANDLERS ---
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}[!] Script interrupted or failed with exit code: $exit_code${RESET}" >&2
        [ -n "${REPORT_FILE:-}" ] && [ -f "$REPORT_FILE" ] && rm -f "$REPORT_FILE"
    fi
    exit $exit_code
}

error_handler() {
    local line=$1
    local command=$2
    local code=${3:-1}
    echo -e "${RED}[!] Error at line $line: Command '$command' exited with status $code${RESET}" >&2
}

trap cleanup EXIT INT TERM
trap 'error_handler ${LINENO} "$BASH_COMMAND" $?' ERR

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

# --- UTILITY FUNCTIONS ---
log_info() {
    echo -e "${GREEN}[+]${RESET} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${RESET} $*" >&2
}

log_error() {
    echo -e "${RED}[-]${RESET} $*" >&2
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || return 1
}

safe_execute() {
    # Execute command with timeout and capture both stdout and stderr
    local cmd_name="$1"
    shift
    local result

    if result=$("$@" 2>/dev/null); then
        echo "$result"
        return 0
    else
        log_warn "Command '$cmd_name' failed or returned no data"
        return 1
    fi
}

# --- PERMISSION CHECK ---
if [ "${EUID:-0}" -ne 0 ] && [ "$(id -u 2>/dev/null || echo 0)" -ne 0 ]; then
    log_error "Please run as root (sudo) to capture complete system diagnostics"
    log_info "Usage: sudo $0"
    exit 1
fi

# --- DEPENDENCY VALIDATION ---
REQUIRED_COMMANDS=(
    "vmstat" "free" "df" "ps" "ss" "hostname" "uname" "uptime"
    "awk" "grep" "tail" "head" "cut" "tr" "wc" "date"
)

OPTIONAL_COMMANDS=(
    "curl" "journalctl" "dmesg" "ip" "column"
)

MISSING_REQUIRED=0
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        log_error "Required command '$cmd' not found"
        MISSING_REQUIRED=1
    fi
done

if [ $MISSING_REQUIRED -eq 1 ]; then
    log_error "Missing required commands. Please install them and try again."
    exit 1
fi

for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if ! check_command "$cmd"; then
        log_warn "Optional command '$cmd' not found - some features will be limited"
    fi
done

# --- CONFIGURATION ---
REPORT_DIR="${REPORT_DIR:-$PWD}"
if [ ! -d "$REPORT_DIR" ] || [ ! -w "$REPORT_DIR" ]; then
    log_error "Cannot write to directory: $REPORT_DIR"
    log_info "Try setting REPORT_DIR environment variable or running from a writable location"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S 2>/dev/null || date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/sys_report_${TIMESTAMP}.html"
TEMP_DIR=$(mktemp -d -t sysdiag-XXXXXX)
[ -n "$TEMP_DIR" ] && trap "rm -rf '$TEMP_DIR'" EXIT INT TERM

log_info "Starting system diagnostic collection..."
log_info "Report will be saved to: $REPORT_FILE"

# --- DATA COLLECTION LAYER ---

# System Information
HOSTNAME=$(safe_execute "hostname" hostname 2>/dev/null || echo "Unknown")
KERNEL=$(safe_execute "kernel version" uname -r 2>/dev/null || echo "Unknown")
UPTIME=$(safe_execute "uptime" uptime -p 2>/dev/null || echo "Unavailable")
CURRENT_DATE=$(date +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || date)

# CPU Metrics - Multiple fallback methods
CPU_USAGE="N/A"
MEM_PCT="N/A"
MEM_USED="N/A"
MEM_TOTAL="N/A"

if check_command vmstat; then
    VM_STATS_FULL=$(safe_execute "vmstat" vmstat 1 2 2>/dev/null | tail -n 1)
    if [ -n "$VM_STATS_FULL" ]; then
        CPU_IDLE=$(echo "$VM_STATS_FULL" | awk '{print $15}' | tr -d -c '0-9' 2>/dev/null)
        if [[ "$CPU_IDLE" =~ ^[0-9]+$ ]] && [ "$CPU_IDLE" -le 100 ]; then
            CPU_USAGE=$((100 - CPU_IDLE))
        fi
    fi
fi

# Fallback CPU calculation using /proc/stat
if [ "$CPU_USAGE" = "N/A" ] && [ -f /proc/stat ]; then
    CPU_DATA=($(head -n1 /proc/stat 2>/dev/null))
    if [ ${#CPU_DATA[@]} -ge 5 ]; then
        CPU_IDLE=${CPU_DATA[4]}
        CPU_TOTAL=$((${CPU_DATA[1]} + ${CPU_DATA[2]} + ${CPU_DATA[3]} + ${CPU_DATA[4]}))
        if [ "$CPU_TOTAL" -gt 0 ]; then
            CPU_USAGE=$((100 - (CPU_IDLE * 100 / CPU_TOTAL)))
        fi
    fi
fi

# Memory Metrics
if check_command free; then
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo "N/A")
    MEM_USED=$(free -h 2>/dev/null | awk '/Mem:/ {print $3}' || echo "N/A")
    MEM_PCT=$(free 2>/dev/null | awk '/Mem:/ {if($2>0) printf "%.1f", $3/$2 * 100; else print "0"}' || echo "N/A")
fi

# Swap Monitoring
SWAP_STATUS="<span class='badge warn'>Not Monitored</span>"
SWAP_IN=0
SWAP_OUT=0

if check_command vmstat && [ -n "${VM_STATS_FULL:-}" ]; then
    SWAP_IN=$(echo "$VM_STATS_FULL" | awk '{print $7}' | tr -d -c '0-9' 2>/dev/null || echo 0)
    SWAP_OUT=$(echo "$VM_STATS_FULL" | awk '{print $8}' | tr -d -c '0-9' 2>/dev/null || echo 0)
    SWAP_IN=${SWAP_IN:-0}
    SWAP_OUT=${SWAP_OUT:-0}

    if [ "$SWAP_IN" -gt 0 ] || [ "$SWAP_OUT" -gt 0 ]; then
        SWAP_STATUS="<span class='badge alert'>Active Swap I/O (In: $SWAP_IN, Out: $SWAP_OUT)</span>"
    else
        SWAP_STATUS="<span class='badge pass'>Nominal</span>"
    fi
fi

# Storage Analysis
DISK_STATUS="<span class='badge pass'>Healthy Storage Caps</span>"
INODE_STATUS="<span class='badge pass'>Healthy File Tables</span>"

if check_command df; then
    DISK_CRIT=$(df -hP -x devtmpfs -x tmpfs -x squashfs 2>/dev/null | awk 'NR>1 && 0+$5 >= 90 {print $1 " (" $5 ")"}' | tr '\n' ' ')
    if [ -n "$DISK_CRIT" ]; then
        DISK_STATUS="<span class='badge alert'>Critically Full: $DISK_CRIT</span>"
    fi

    INODE_CRIT=$(df -iP -x devtmpfs -x tmpfs -x squashfs 2>/dev/null | awk 'NR>1 && 0+$5 >= 90 {print $1 " (" $5 ")"}' | tr '\n' ' ')
    if [ -n "$INODE_CRIT" ]; then
        INODE_STATUS="<span class='badge alert'>Inode Saturation: $INODE_CRIT</span>"
    fi
fi

# Kernel Interventions - OOM and Thermal
OOM_STATUS="<span class='badge warn'>Not Checked</span>"
THERM_STATUS="<span class='badge warn'>Not Checked</span>"

if check_command journalctl; then
    if OOM_COUNT=$(journalctl -k -b 2>/dev/null | grep -ci "invoked oom-killer"); then
        OOM_COUNT=${OOM_COUNT:-0}
        if [ "$OOM_COUNT" -gt 0 ]; then
            OOM_STATUS="<span class='badge alert'>OOM Killer Triggered ($OOM_COUNT times)</span>"
        else
            OOM_STATUS="<span class='badge pass'>Clear</span>"
        fi
    fi
else
    OOM_STATUS="<span class='badge warn'>journalctl unavailable</span>"
fi

if check_command dmesg; then
    if THERM_COUNT=$(dmesg 2>/dev/null | grep -ciE 'critical temperature|thermal throttling'); then
        THERM_COUNT=${THERM_COUNT:-0}
        if [ "$THERM_COUNT" -gt 0 ]; then
            THERM_STATUS="<span class='badge alert'>Thermal Throttling Engaged ($THERM_COUNT events)</span>"
        else
            THERM_STATUS="<span class='badge pass'>Clear</span>"
        fi
    fi
else
    THERM_STATUS="<span class='badge warn'>dmesg unavailable</span>"
fi

# Network Diagnostics
PUBLIC_IP="N/A"
NET_EGRESS_STATUS="<span class='badge warn'>Not Tested</span>"

if check_command curl; then
    PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "Offline/Timed Out")

    if curl -s --max-time 3 --head https://www.google.com >/dev/null 2>&1; then
        NET_EGRESS_STATUS="<span class='badge pass'>Active & Online</span>"
    else
        NET_EGRESS_STATUS="<span class='badge alert'>Offline / Blocked</span>"
    fi
else
    PUBLIC_IP="curl unavailable"
    log_warn "curl not found - network connectivity checks skipped"
fi

# Build Network Interface Table
NET_INTERFACES_DATA="Network interface data unavailable"
if check_command ip; then
    NET_INTERFACES_DATA=$(
        printf "%-10s %-15s %s\n" "Interface" "IPv4" "IPv6"
        printf "%-10s %-15s %s\n" "---------" "---------------" "----------------"

        if [ -d /sys/class/net ]; then
            for dev in /sys/class/net/*; do
                iface=$(basename "$dev")
                [ "$iface" = "lo" ] && continue

                ipv4=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
                ipv6=$(ip -6 addr show dev "$iface" 2>/dev/null | awk '/inet6 / {print $2}' | cut -d/ -f1 | head -n1)

                printf "%-10s %-15s %s\n" "$iface" "${ipv4:-None}" "${ipv6:-None}"
            done
        fi
    ) || NET_INTERFACES_DATA="Failed to collect network interface data"
fi

# Process and Socket Information
TOP_PROCESSES="Process information unavailable"
if check_command ps; then
    TOP_PROCESSES=$(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | grep -v 'ps' | head -n 11) || \
    TOP_PROCESSES="Failed to retrieve process list"
fi

SOCKET_DATA="Socket information unavailable"
if check_command ss; then
    SOCKET_DATA=$(ss -tulnp 2>/dev/null | awk 'NR==1 || /LISTEN/ {print $1, $5, $7}' | column -t) || \
    SOCKET_DATA="Failed to retrieve socket information"
fi

# Storage Details
FS_DATA="Filesystem information unavailable"
if check_command df; then
    FS_DATA=$(df -h -x devtmpfs -x tmpfs -x squashfs 2>/dev/null)
    FS_DATA="${FS_DATA}\n\nInodes:\n$(df -i -x devtmpfs -x tmpfs -x squashfs 2>/dev/null)"
fi

# System Events
KERNEL_EVENTS="Kernel event log unavailable"
if check_command journalctl; then
    KERNEL_EVENTS=$(journalctl -k -b -p 0..4 -n 15 --no-pager 2>/dev/null) || \
    KERNEL_EVENTS="No critical kernel events registered for current boot"
fi

HARDWARE_ERRORS="Hardware diagnostic data unavailable"
if check_command dmesg; then
    HARDWARE_ERRORS=$(dmesg 2>/dev/null | grep -iE 'hardware error|corrupted|firmware crash' | tail -n 15) || \
    HARDWARE_ERRORS="No explicit hardware degradation faults tracked"
fi

# --- HTML REPORT GENERATION ---
log_info "Generating HTML report..."

cat > "$TEMP_DIR/report.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Diagnostic Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: #f8f9fa;
            color: #333;
            line-height: 1.6;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .header h1 { font-size: 28px; margin-bottom: 10px; }
        .header .meta { opacity: 0.9; font-size: 14px; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 2px 15px rgba(0,0,0,0.05);
            transition: transform 0.2s;
        }
        .card:hover { transform: translateY(-2px); }
        .card h3 {
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #6c757d;
            margin-bottom: 15px;
            font-weight: 600;
        }
        .metric {
            font-size: 32px;
            font-weight: bold;
            color: #2d3748;
            margin-bottom: 5px;
        }
        .submetric { color: #718096; font-size: 13px; }
        .section {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 2px 15px rgba(0,0,0,0.05);
            margin-bottom: 20px;
        }
        .section h2 {
            font-size: 18px;
            color: #2d3748;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e2e8f0;
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .pass { background: #d4edda; color: #155724; }
        .warn { background: #fff3cd; color: #856404; }
        .alert { background: #f8d7da; color: #721c24; }
        pre {
            background: #2d3748;
            color: #e2e8f0;
            padding: 20px;
            border-radius: 8px;
            overflow-x: auto;
            font-family: "SF Mono", "Monaco", "Inconsolata", "Fira Code", monospace;
            font-size: 13px;
            line-height: 1.6;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
        }
        th {
            background: #f7fafc;
            color: #4a5568;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-weight: 600;
        }
        tr:hover td { background: #f7fafc; }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
        }
        .status-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid #e2e8f0;
        }
        .timestamp {
            text-align: right;
            font-size: 12px;
            color: #a0aec0;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
HTMLEOF

# Append dynamic content
cat >> "$TEMP_DIR/report.html" << EOF
        <div class="header">
            <h1>🖥️ System Diagnostics Report</h1>
            <div class="meta">
                <strong>Hostname:</strong> ${HOSTNAME} &nbsp;|&nbsp;
                <strong>Kernel:</strong> ${KERNEL} &nbsp;|&nbsp;
                <strong>Generated:</strong> ${CURRENT_DATE}
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h3>📊 CPU Utilization</h3>
                <div class="metric">${CPU_USAGE}%</div>
                <div class="submetric">Active compute load</div>
            </div>
            <div class="card">
                <h3>🧠 Memory Usage</h3>
                <div class="metric">${MEM_PCT}%</div>
                <div class="submetric">${MEM_USED} / ${MEM_TOTAL}</div>
            </div>
            <div class="card">
                <h3>🔍 System Health</h3>
                <div class="status-grid">
                    <div class="status-item">
                        <span>Swap I/O:</span>
                        ${SWAP_STATUS}
                    </div>
                    <div class="status-item">
                        <span>Storage:</span>
                        ${DISK_STATUS}
                    </div>
                    <div class="status-item">
                        <span>Inodes:</span>
                        ${INODE_STATUS}
                    </div>
                </div>
            </div>
            <div class="card">
                <h3>⚡ Kernel Events</h3>
                <div class="status-grid">
                    <div class="status-item">
                        <span>OOM Killer:</span>
                        ${OOM_STATUS}
                    </div>
                    <div class="status-item">
                        <span>Thermal:</span>
                        ${THERM_STATUS}
                    </div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>🔝 Top 10 CPU-Intensive Processes</h2>
            <pre>${TOP_PROCESSES}</pre>
        </div>

        <div class="section">
            <h2>💾 Filesystem Analysis</h2>
            <pre>${FS_DATA}</pre>
        </div>

        <div class="section">
            <h2>🌐 Network Diagnostics</h2>
            <table>
                <tr><th>Public IPv4</th><td>${PUBLIC_IP}</td></tr>
                <tr><th>Connectivity Status</th><td>${NET_EGRESS_STATUS}</td></tr>
                <tr><th>System Uptime</th><td>${UPTIME}</td></tr>
            </table>

            <h3 style="margin-top: 20px;">Network Interfaces</h3>
            <pre>${NET_INTERFACES_DATA}</pre>

            <h3 style="margin-top: 20px;">Listening Sockets</h3>
            <pre>${SOCKET_DATA}</pre>
        </div>

        <div class="section">
            <h2>📋 System Event Logs</h2>
            <h3>Critical Kernel Events (Current Boot)</h3>
            <pre>${KERNEL_EVENTS}</pre>

            <h3 style="margin-top: 20px;">Hardware Fault Tracking</h3>
            <pre>${HARDWARE_ERRORS}</pre>
        </div>

        <div class="timestamp">
            Report generated by System Diagnostic Tool v2.0 | ${HOSTNAME} | ${CURRENT_DATE}
        </div>
    </div>
</body>
</html>
EOF

# Finalize report
if mv "$TEMP_DIR/report.html" "$REPORT_FILE" 2>/dev/null; then
    # Compress if gzip is available and file is larger than 1MB
    if check_command gzip && [ -f "$REPORT_FILE" ] && [ "$(stat -f%z "$REPORT_FILE" 2>/dev/null || stat -c%s "$REPORT_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
        gzip -f "$REPORT_FILE" 2>/dev/null && REPORT_FILE="${REPORT_FILE}.gz"
        log_info "Report compressed due to size"
    fi

    # Clean up old reports (keep last 30 days)
    if [ -d "$REPORT_DIR" ]; then
        find "$REPORT_DIR" -name "sys_report_*.html*" -mtime +30 -delete 2>/dev/null
        log_info "Cleaned up reports older than 30 days"
    fi

    echo
    echo "========================================="
    log_info "Diagnostic report generated successfully!"
    echo "     ${CYAN}${REPORT_FILE}${RESET}"
    echo "========================================="

    # Offer to open in browser if available
    if check_command xdg-open; then
        echo -n "Open in browser? (y/N): "
        read -r OPEN_BROWSER
        if [[ "$OPEN_BROWSER" =~ ^[Yy]$ ]]; then
            xdg-open "$REPORT_FILE" 2>/dev/null || log_warn "Could not open browser"
        fi
    fi
else
    log_error "Failed to write report file"
    exit 1
fi
