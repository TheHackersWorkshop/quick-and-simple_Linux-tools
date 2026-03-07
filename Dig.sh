#!/bin/bash

display_menu() {
    echo -e "\n--- DNS Query Tool ---"
    echo "1. Full Dig (Raw)    5. Nameservers (NS)   9. Propagation Check"
    echo "2. IPv4 (A)          6. Text (TXT)         10. Reverse DNS"
    echo "3. IPv6 (AAAA)       7. Canonical (CNAME)  11. Trace (Full Path)"
    echo "4. Mail (MX)         8. Authority (SOA)    0. Exit"
    echo "----------------------"
}

# Helper to handle the "Blank to Exit" and Domain input
get_domain() {
    read -p "Enter Domain (or Enter to go back): " domain
    if [[ -z "$domain" ]]; then
        return 1
    fi
    return 0
}

propagation_check() {
    if get_domain; then
        echo -e "\nChecking Propagation for: $domain"
        printf "%-25s %-s\n" "Provider" "Result"
        printf "%-25s %-s\n" "--------" "------"

        # Checking against major global anycast networks
        for server in "8.8.8.8 (Google)" "1.1.1.1 (Cloudflare)" "208.67.222.222 (OpenDNS)" "9.9.9.9 (Quad9)"; do
            ip=$(echo $server | awk '{print $1}')
            name=$(echo $server | cut -d' ' -f2-)
            res=$(dig @$ip "$domain" +short)
            printf "%-25s %-s\n" "$name" "${res:-[No Record]}"
        done
    fi
}

while true; do
    display_menu
    read -p "Choice: " choice

    case $choice in
        1) if get_domain; then dig "$domain"; fi ;;
        2) if get_domain; then dig "$domain" A +short; fi ;;
        3) if get_domain; then dig "$domain" AAAA +short; fi ;;
        4) if get_domain; then dig "$domain" MX +short; fi ;;
        5) if get_domain; then dig "$domain" NS +short; fi ;;
        6) if get_domain; then dig "$domain" TXT +short; fi ;;
        7) if get_domain; then dig "$domain" CNAME +short; fi ;;
        8) if get_domain; then dig "$domain" SOA +short; fi ;;
        9) propagation_check ;;
        10)
            read -p "Enter IP for Reverse Lookup: " ip
            [[ -n "$ip" ]] && dig -x "$ip" +short
            ;;
        11)
            if get_domain; then
                echo -e "\nTracing DNS path for $domain..."
                echo "----------------------------------"
                dig "$domain" +trace
            fi
            ;;
        0|"") echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
