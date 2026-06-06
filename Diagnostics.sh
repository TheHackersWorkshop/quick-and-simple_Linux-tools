#!/bin/bash

# Ensure script is run as root to parse system-level metrics and ports
if [ "$EUID" -ne 0 ] 2>/dev/null; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Critical: Please run as root (sudo) to capture all hardware diagnostics."
    exit 1
  fi
fi

# Configuration - Saves directly to your current directory
REPORT_DIR="$PWD"
REPORT_FILE="${REPORT_DIR}/sys_report_$(date +%Y%m%d_%H%M%S).html"

# --- DATA COLLECTION LAYER ---

HOSTNAME=$(hostname)
KERNEL=$(uname -r)
UPTIME=$(uptime -p)

# Single vmstat call to optimize performance
VM_STATS_FULL=$(vmstat 1 2 | tail -n 1)

# CPU Utilization
CPU_IDLE=$(echo "$VM_STATS_FULL" | awk '{print $15}' | tr -d -c '0-9')
CPU_USAGE=$((100 - ${CPU_IDLE:-0}))

# Memory & Swap Saturation
MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
MEM_PCT=$(free | awk '/Mem:/ {printf "%.1f", $3/$2 * 100}')

SWAP_IN=$(echo "$VM_STATS_FULL" | awk '{print $7}' | tr -d -c '0-9')
SWAP_OUT=$(echo "$VM_STATS_FULL" | awk '{print $8}' | tr -d -c '0-9')

if [ "${SWAP_IN:-0}" -gt 0 ] || [ "${SWAP_OUT:-0}" -gt 0 ]; then
    SWAP_STATUS="<span class='badge alert'>Active Swap I/O</span>"
else
    SWAP_STATUS="<span class='badge pass'>Nominal</span>"
fi

# Storage Space & Inodes
DISK_CRIT=$(df -hP -x devtmpfs -x tmpfs -x squashfs 2>/dev/null | awk '0+$5 >= 90 {print $1 " (" $5 ")"}')
if [ -n "$DISK_CRIT" ]; then
    DISK_STATUS="<span class='badge alert'>Critically Full: $DISK_CRIT</span>"
else
    DISK_STATUS="<span class='badge pass'>Healthy Storage Caps</span>"
fi

INODE_CRIT=$(df -iP -x devtmpfs -x tmpfs -x squashfs 2>/dev/null | awk '0+$5 >= 90 {print $1 " (" $5 ")"}')
if [ -n "$INODE_CRIT" ]; then
    INODE_STATUS="<span class='badge alert'>Inode Saturation: $INODE_CRIT</span>"
else
    INODE_STATUS="<span class='badge pass'>Healthy File Tables</span>"
fi

# FIXED: Strict match for actual kernel OOM invocations rather than generic text hits
OOM_COUNT=$(journalctl -k -b | grep -i "invoked oom-killer" | wc -l)
if [ "${OOM_COUNT:-0}" -gt 0 ]; then
    OOM_STATUS="<span class='badge alert'>OOM Killer Triggered ($OOM_COUNT times)</span>"
else
    OOM_STATUS="<span class='badge pass'>Clear</span>"
fi

# FIXED: Only count critical hardware critical thermal trips, ignoring standard ACPI polling
THERM_COUNT=$(dmesg | grep -iE 'critical temperature|thermal throttling' | wc -l)
if [ "${THERM_COUNT:-0}" -gt 0 ]; then
    THERM_STATUS="<span class='badge alert'>Thermal Throttling Engaged ($THERM_COUNT)</span>"
else
    THERM_STATUS="<span class='badge pass'>Clear</span>"
fi

# Network Core Diagnostics
PUBLIC_IP=$(curl -s --max-time 2 ifconfig.me || echo "Offline/Timed Out")

if curl -s --max-time 2 https://www.google.com >/dev/null; then
    NET_EGRESS_STATUS="<span class='badge pass'>Active & Online</span>"
else
    NET_EGRESS_STATUS="<span class='badge alert'>Offline / Blocked</span>"
fi

# Pre-build Network Table
NET_INTERFACES_DATA=$(
    printf "%-10s %-15s %s\n" "Interface" "IPv4" "IPv6"
    printf "%-10s %-15s %s\n" "---------" "---------------" "----------------"

    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        [ "$iface" = "lo" ] && continue

        ipv4=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
        ipv6=$(ip -6 addr show dev "$iface" 2>/dev/null | awk '/inet6 / {print $2}' | cut -d/ -f1 | head -n 1)

        printf "%-10s %-15s %s\n" "$iface" "${ipv4:-None}" "${ipv6:-None}"
    done
)

# --- GENERATION LAYER (HTML OUTPUT) ---

cat << EOF > "$REPORT_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>System Diagnostic Report - $HOSTNAME</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #f4f6f9; color: #333; margin: 0; padding: 20px; }
        .container { max-width: 1100px; margin: 0 auto; }
        header { background: #2c3e50; color: #fff; padding: 20px; border-radius: 8px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
        header h1 { margin: 0; font-size: 24px; }
        header p { margin: 5px 0 0 0; color: #bdc3c7; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 20px; }
        .card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
        .card h3 { margin: 0 0 15px 0; color: #7f8c8d; font-size: 14px; text-transform: uppercase; letter-spacing: 1px; }
        .metric { font-size: 28px; font-weight: bold; color: #2c3e50; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; text-transform: uppercase; }
        .pass { background: #d4edda; color: #155724; }
        .warn { background: #fff3cd; color: #856404; }
        .alert { background: #f8d7da; color: #721c24; }
        .section { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); margin-bottom: 20px; }
        .section h2 { margin-top: 0; font-size: 18px; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; color: #2c3e50; }
        pre { background: #2d3748; color: #f7fafc; padding: 15px; border-radius: 6px; overflow-x: auto; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 13px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; }
        table { width: 100%; border-collapse: collapse; text-align: left; }
        th, td { padding: 12px; border-bottom: 1px solid #e2e8f0; }
        th { background: #f8fafc; color: #475569; font-size: 13px; text-transform: uppercase; }
    </style>
</head>
<body>
<div class="container">

    <header>
        <div>
            <h1>System Diagnostics: $HOSTNAME</h1>
            <p>Kernel: $KERNEL | Run Date: $(date +"%Y-%m-%d %H:%M:%S %Z")</p>
        </div>
        <div style="text-align: right;">
            <span class="badge pass" style="font-size:14px; padding:8px 12px;">Report Generated</span>
        </div>
    </header>

    <div class="grid">
        <div class="card">
            <h3>CPU Compute Load</h3>
            <div class="metric">${CPU_USAGE}%</div>
            <p style="margin: 5px 0 0 0; color:#7f8c8d; font-size:12px;">Active task utilization</p>
        </div>
        <div class="card">
            <h3>Physical RAM</h3>
            <div class="metric">${MEM_PCT}%</div>
            <p style="margin: 5px 0 0 0; color:#7f8c8d; font-size:12px;">Used: $MEM_USED / Total: $MEM_TOTAL</p>
        </div>
        <div class="card">
            <h3>System Status Check</h3>
            <div style="margin-bottom: 8px;">Swap I/O: $SWAP_STATUS</div>
            <div style="margin-bottom: 8px;">Storage: $DISK_STATUS</div>
            <div>File Tables: $INODE_STATUS</div>
        </div>
        <div class="card">
            <h3>Kernel Interventions</h3>
            <div style="margin-bottom: 8px;">OOM Events: $OOM_STATUS</div>
            <div>Thermal State: $THERM_STATUS</div>
        </div>
    </div>

    <div class="section">
        <h2>Top 10 Computational Intensive Processes</h2>
        <pre>$(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | grep -v 'ps' | head -n 11)</pre>
    </div>

    <div class="section">
        <h2>File System Capacities & Inode Allocations</h2>
        <pre>$(df -h -x devtmpfs -x tmpfs -x squashfs 2>/dev/null)

Inodes:
$(df -i -x devtmpfs -x tmpfs -x squashfs 2>/dev/null)</pre>
    </div>

    <div class="section">
        <h2>Network Interface Routing & Connectivity Matrix</h2>
        <table style="margin-bottom: 15px;">
            <tr><th>Public IPv4 Egress</th><td>$PUBLIC_IP</td></tr>
            <tr><th>System Connection State</th><td>$NET_EGRESS_STATUS</td></tr>
            <tr><th>System Uptime Status</th><td>$UPTIME</td></tr>
        </table>

        <h3>Local Interfaces and Addresses (Full Stack Scan)</h3>
        <pre>$NET_INTERFACES_DATA</pre>

        <h3>Established & Listening Sockets</h3>
        <pre>$(ss -tulnp | awk 'NR==1 || /LISTEN/ {print $1, $5, $7}' | column -t)</pre>
    </div>

    <div class="section">
        <h2>Recent Critical System Events (Errors, Hardware & Faults)</h2>
        <h3>Prioritized Kernel Log Entries (Level 0-4 for Current Boot)</h3>
        <pre>$(journalctl -k -b -p 0..4 -n 15 --no-pager 2>/dev/null || echo "No critical kernel events registered.")</pre>

        <h3>Device Driver Hardware Tracking Ring Buffer</h3>
        <pre>$(dmesg | grep -iE 'hardware error|corrupted|firmware crash' | tail -n 15 || echo "No explicit hardware degradation faults tracked.")</pre>
    </div>

</div>
</body>
</html>
EOF

COLOR_CYAN='\033[1;36m'
COLOR_RESET='\033[0m'

printf "\n=========================================\n"
printf " [+] Diagnostic Engine Updated!\n"
printf " [+] Structured HTML Report compiled to:\n"
printf "     ${COLOR_CYAN}%s${COLOR_RESET}\n" "${REPORT_FILE}"
printf "=========================================\n"
