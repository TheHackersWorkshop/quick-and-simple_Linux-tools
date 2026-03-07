#!/bin/bash

echo "--- Directory File Indexer ---"
echo "(Leave blank to exit)"

# 1. Input with expansion (~/Desktop, etc.)
read -p "Enter directory to scan: " raw_path
[[ -z "$raw_path" ]] && exit 0

folder_path=$(eval echo "$raw_path")

# 2. Validation
if [ ! -d "$folder_path" ]; then
    echo "Error: Directory '$folder_path' not found!"
    exit 1
fi

# 3. Clean Output
output_file="./files_list.txt"

# -type f: Files only
# -maxdepth 1: Stay in this folder
# sort: Alphabetical order
find "$folder_path" -maxdepth 1 -type f -printf "%f\n" | sort > "$output_file"

# 4. Summary
count=$(wc -l < "$output_file")

if [ "$count" -gt 0 ]; then
    echo "--------------------------------"
    echo "Success: $count files indexed."
    echo "Saved to: $output_file"
    echo "First 3 entries:"
    head -n 3 "$output_file"
    echo "--------------------------------"
else
    echo "No files found in that directory."
    rm -f "$output_file"
fi
