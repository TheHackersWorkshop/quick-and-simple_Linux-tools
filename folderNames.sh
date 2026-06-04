#!/bin/bash

echo "--- Media Library Indexer ---"

read -p "Enter Media Directory: " raw_path
[[ -z "$raw_path" ]] && exit 0
folder_path=$(eval echo "$raw_path")

if [ ! -d "$folder_path" ]; then
    echo "Error: Directory not found!"
    exit 1
fi

# Extract the base name of the parent folder
PARENT_NAME=$(basename "$folder_path")

# Define the dynamic output file name based on the parent folder
output_file="./${PARENT_NAME}_manifest.txt"

# sort -f: Case-insensitive alphabetical sort
find "$folder_path" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort -f > "$output_file"

# Summary and Preview
count=$(wc -l < "$output_file")

if [ "$count" -gt 0 ]; then
    echo "--------------------------------"
    echo "Found $count movie folders."
    echo "List saved to: $output_file"
    echo "--------------------------------"
    echo "Last 3 folders alphabetically (Verification):"
    tail -n 3 "$output_file"
else
    echo "No sub-folders found in $folder_path."
    rm -f "$output_file"
fi
