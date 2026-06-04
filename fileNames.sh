#!/bin/bash

echo "--- Directory File Indexer ---"
echo "(Leave blank to exit)"

read -p "Enter directory to scan: " raw_path
[[ -z "$raw_path" ]] && exit 0

folder_path=$(eval echo "$raw_path")

if [ ! -d "$folder_path" ]; then
    echo "Error: Directory '$folder_path' not found!"
    exit 1
fi

# Extract the base name of the parent directory
PARENT_NAME=$(basename "$folder_path")

# 3. Dynamic Output File Destination
output_file="./${PARENT_NAME}_files_list.txt"

# sort: Alphabetical order
find "$folder_path" -maxdepth 1 -type f -printf "%f\n" | sort > "$output_file"

count=$(wc -l < "$output_file")

if [ "$count" -gt 0 ]; then
    echo "--------------------------------"
    echo "Success: $count files indexed."
    echo "Saved to: $output_file"
    echo "First 3 entries (Verification):"
    head -n 3 "$output_file"
    echo "--------------------------------"
else
    echo "No files found in that directory."
    rm -f "$output_file"
fi
