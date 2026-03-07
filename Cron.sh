#!/bin/bash

# Ensure we clean up temp files even if script is interrupted
trap 'rm -f /tmp/cron_temp.*' EXIT
CRONTEMP="/tmp/cron_temp.$$"

print_menu() {
    echo "--- Cron Manager (Admin Mode) ---"
    echo "1) List Cron Jobs"
    echo "2) Add Cron Job"
    echo "3) Delete Cron Job"
    echo "4) Disable Cron Job"
    echo "5) Enable Cron Job"
    echo "6) Exit"
    echo ""
}

# Helper to decide if we need sudo
use_sudo_for_user() {
    [[ "$1" != "$(whoami)" ]] || [[ "$1" == "root" ]]
}

get_crontab() {
    local user="$1"
    if use_sudo_for_user "$user"; then
        sudo crontab -l -u "$user" 2>/dev/null
    else
        crontab -l -u "$user" 2>/dev/null
    fi
}

save_crontab() {
    local user="$1"
    local file="$2"
    if use_sudo_for_user "$user"; then
        sudo crontab -u "$user" "$file"
    else
        crontab -u "$user" "$file"
    fi
}

list_cron_jobs() {
    read -p "Enter user (blank for current): " user
    user=${user:-$(whoami)}
    echo -e "\nCurrent Cron Jobs for [$user]:"
    local jobs
    jobs=$(get_crontab "$user")
    if [[ -z "$jobs" ]]; then
        echo "[No jobs found]"
    else
        echo "$jobs" | nl -w2 -s'. '
    fi
}

add_cron_job() {
    read -p "Run as user [default: $(whoami)]: " user
    user=${user:-$(whoami)}

    echo -e "\nSchedule Specification:"
    echo "1) Custom (min hour dom mon dow)"
    echo "2) @reboot (Once at startup)"
    echo "3) @daily  (Midnight)"
    echo "4) Cancel"
    read -p "Choice [1-4]: " t_choice

    case $t_choice in
        1) read -p "Enter Cron String (e.g. 0 5 * * *): " schedule ;;
        2) schedule="@reboot" ;;
        3) schedule="@daily" ;;
        *) echo "Aborted."; return ;;
    esac

    read -p "Full command to run: " cmd
    [[ -z "$cmd" ]] && { echo "Empty command. Aborting."; return; }

    # Validate command exists
    if ! command -v "${cmd%% *}" &>/dev/null; then
        read -p "Warning: '${cmd%% *}' not in path. Add anyway? (y/n): " confirm
        [[ "$confirm" != "y" ]] && return
    fi

    get_crontab "$user" > "$CRONTEMP" 2>/dev/null || touch "$CRONTEMP"
    echo "$schedule $cmd" >> "$CRONTEMP"
    save_crontab "$user" "$CRONTEMP"
    echo "Job added."
}

# Simplified Disable: Just toggles the '#'
disable_cron_job() {
    read -p "User to modify [default: $(whoami)]: " user
    user=${user:-$(whoami)}
    get_crontab "$user" > "$CRONTEMP"

    list_cron_jobs "$user"
    read -p "Enter job number to DISABLE: " num

    # Use sed to prepend #
    sed -i "${num}s/^/#/" "$CRONTEMP"
    save_crontab "$user" "$CRONTEMP"
    echo "Job #$num commented out."
}

enable_cron_job() {
    read -p "User to modify [default: $(whoami)]: " user
    user=${user:-$(whoami)}
    get_crontab "$user" > "$CRONTEMP"

    echo -e "\nCurrently Disabled Jobs:"
    grep -n "^#" "$CRONTEMP" || echo "None found."

    read -p "Enter line number to ENABLE: " num
    # Remove the first # from that specific line
    sed -i "${num}s/^#//" "$CRONTEMP"
    save_crontab "$user" "$CRONTEMP"
    echo "Job #$num restored."
}

while true; do
    print_menu
    read -p "Option: " option
    case "$option" in
        1) list_cron_jobs ;;
        2) add_cron_job ;;
        3) # Reuse logic from delete
           read -p "User: " user
           user=${user:-$(whoami)}
           get_crontab "$user" > "$CRONTEMP"
           list_cron_jobs "$user"
           read -p "Delete #? " num
           sed -i "${num}d" "$CRONTEMP"
           save_crontab "$user" "$CRONTEMP"
           ;;
        4) disable_cron_job ;;
        5) enable_cron_job ;;
        6) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
