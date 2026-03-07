#!/bin/bash

echo "--- Media Library Indexer ---"

# 1. Input with ~ expansion
read -p "Enter Media Directory: " raw_path
[[ -z "$raw_path" ]] && exit 0
folder_path=$(eval echo "$raw_path")

if [ ! -d "$folder_path" ]; then
    echo "Error: Directory not found!"
    exit 1
fi

output_file="./library_manifest.txt"

# 2. The Clean Find
# -mindepth 1: This is the "magic" that skips the parent folder itself
# -type d: Directories only
# sort -f: Case-insensitive alphabetical sort
find "$folder_path" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort -f > "$output_file"

# 3. Summary and Preview
count=$(wc -l < "$output_file")

if [ "$count" -gt 0 ]; then
    echo "--------------------------------"
    echo "Found $count movie folders."
    echo "List saved to: $output_file"
    echo "--------------------------------"
    echo "Last 3 added (alphabetically):"
    tail -n 3 "$output_file"
else
    echo "No sub-folders found in $folder_path."
    rm -f "$output_file"
fi
