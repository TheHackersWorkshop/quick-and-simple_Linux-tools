#!/bin/bash

ALIAS_FILE="/etc/.aliases"

# 1. Elevate early
if [ "$EUID" -ne 0 ]; then
    echo "Elevating to root to modify $ALIAS_FILE..."
    exec sudo "$0" "$@"
fi

[ ! -f "$ALIAS_FILE" ] && touch "$ALIAS_FILE"

echo "--- Global Alias Manager ---"
echo "(Leave blank and press Enter to cancel)"
echo ""

# 2. Show only the last few entries for context (Avoids the wall of text)
echo "--- Last 5 Aliases Added ---"
if [ -s "$ALIAS_FILE" ]; then
    # We filter for lines actually starting with 'alias' and show the last 5
    grep "^alias " "$ALIAS_FILE" | tail -n 5 | sed "s/alias //g" | column -t -s '='
else
    echo "(No aliases defined yet)"
fi
echo "------------------------------------------"
echo ""

# 3. Alias Name Input (with Escape)
read -p "Enter the NEW alias name: " alias_name
if [[ -z "$alias_name" ]]; then
    echo "Exiting."
    exit 0
fi

# Check for duplicates
if grep -q "alias ${alias_name}=" "$ALIAS_FILE"; then
    echo "Error: Alias '$alias_name' already exists."
    exit 1
fi

# 4. Command Input (with Escape)
read -p "Enter the command for '$alias_name': " cmd_raw
if [[ -z "$cmd_raw" ]]; then
    echo "Exiting."
    exit 0
fi

# 5. Confirmation & Safe Writing
alias_line="alias $alias_name='$cmd_raw'"

echo -e "\nProposed: $alias_line"
read -p "Is this correct? (y/n): " confirmation

if [[ "$confirmation" =~ ^[Yy]$ ]]; then
    # Append to the end of the file
    echo "$alias_line" >> "$ALIAS_FILE"
    echo "Success! Alias added."
    echo "Run 'source $ALIAS_FILE' to use it now."
else
    echo "Aborted."
fi
