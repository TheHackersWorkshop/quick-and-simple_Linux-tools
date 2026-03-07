#!/bin/bash

echo "--- Universal Disk/File Imager ---"

# 1. Show drives so the user doesn't have to guess /dev/ paths
echo "Current Storage Devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v "loop"
echo "----------------------------------"

# 2. Inputs
read -p "Source (if=): " infile
[[ -z "$infile" ]] && exit 0

read -p "Destination (of=): " outfile
[[ -z "$outfile" ]] && exit 0

# 3. Safety logic: Is the destination a physical disk?
if [[ "$outfile" == /dev/* ]]; then
    TYPE_MSG="WARNING: Physical Disk Overwrite!"
else
    TYPE_MSG="Creating image file."
fi

echo -e "\nSUMMARY:"
echo "----------------------------------"
echo "FROM: $infile"
echo "TO:   $outfile"
echo "MODE: $TYPE_MSG"
echo "----------------------------------"
read -p "Proceed with copy? (y/n): " confirm

if [[ "$confirm" == "y" ]]; then
    # conv=fsync ensures the buffer is flushed to the hardware
    sudo dd if="$infile" of="$outfile" bs=2M status=progress conv=fsync
    echo -e "\nOperation Finished."
else
    echo "Aborted."
fi
