#!/bin/bash

# 1. Check for argument
if [ -z "$1" ]; then
    echo "Usage: killproc <PID|process name>"
    exit 1
fi

# 2. Elevate to root (Preserve environment)
if [ "$EUID" -ne 0 ]; then
    echo "Elevating privileges with sudo..."
    exec sudo -E "$0" "$@"
fi

target=$1

kill_by_name() {
    # -f: Match full command line
    # -i: CASE-INSENSITIVE (this fixes your Maelstrom issue)
    # grep -v: Exclude this script's PID ($$) and the script name
    pids=$(pgrep -fi "$1" | grep -v -e "$$" -e "killproc")

    if [ -z "$pids" ]; then
        echo "No process found matching: $1 (searched case-insensitively)"
        exit 1
    fi

    echo "Found the following processes (Case-Insensitive):"
    echo
    printf "%-8s %-10s %-s\n" "PID" "USER" "COMMAND"
    echo "----------------------------------------------------------"

    # Use a loop that handles multiple PIDs correctly
    for pid in $pids; do
        user=$(ps -p "$pid" -o user= 2>/dev/null)
        cmd=$(ps -p "$pid" -o args= 2>/dev/null | cut -c 1-80)

        if [ -n "$user" ]; then
            printf "%-8s %-10s %s\n" "$pid" "$user" "$cmd"
        fi
    done
    echo

    read -p "Enter PID(s) to kill, or type 'all': " input

    if [[ "$input" == "all" ]]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null && echo "Killed PID $pid"
        done
    elif [[ "$input" =~ ^[0-9\ ]+$ ]]; then
        for pid in $input; do
            kill -9 "$pid" 2>/dev/null && echo "Killed PID $pid" || echo "Failed to kill PID $pid"
        done
    else
        echo "Action cancelled."
    fi
}

# Main logic
if [[ "$target" =~ ^[0-9]+$ ]]; then
    kill -9 "$target" 2>/dev/null && echo "Killed PID $target" || echo "PID $target not found."
else
    kill_by_name "$target"
fi
