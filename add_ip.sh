#!/bin/bash

# 1. Elevate early
if [ "$EUID" -ne 0 ]; then
    echo "Elevating to root for /etc/hosts access..."
    exec sudo "$0" "$@"
fi

echo "--- Local DNS Entry Tool ---"
echo "(Leave blank and press Enter at any time to cancel/exit)"
echo ""

# 2. Display current custom entries
echo "--- Current /etc/hosts Entries ---"
printf "%-15s %-s\n" "IP Address" "Hostname"
echo "----------------------------------"
grep -v -E "^(#|127\.0\.0\.1|::1|localhost|ff02|ip6-)" /etc/hosts | awk '{printf "%-15s %-s\n", $1, $2}'
echo "----------------------------------"
echo ""

# 3. Hostname Input
read -p "Enter the NEW hostname: " name
if [[ -z "$name" ]]; then
    echo "No hostname entered. Exiting."
    exit 0
fi

# Check if name exists
if grep -qw "$name" /etc/hosts; then
    echo "Warning: '$name' already exists."
    read -p "Add another entry for this name? (y/n): " confirm
    [[ "$confirm" != "y" ]] && { echo "Aborted."; exit 0; }
fi

# 4. IP Input
read -p "Enter the IP address for $name: " ip
if [[ -z "$ip" ]]; then
    echo "No IP entered. Exiting."
    exit 0
fi

# 5. IP Validation
if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: '$ip' is not a valid IPv4 address. Entry not added."
    exit 1
fi

# 6. Commit and show result
echo -e "$ip\t$name" | tee -a /etc/hosts > /dev/null

echo -e "\nSuccess! Entry added."
echo -e "New mapping: $ip -> $name"
