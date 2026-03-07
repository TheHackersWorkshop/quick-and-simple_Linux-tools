#!/usr/bin/env python3
import os
import pwd
import grp
import stat
import sys
from datetime import datetime

def check_permissions():
    # 1. Automatic Elevation (Peer-to-peer style: "I'll handle the sudo for you")
    if os.geteuid() != 0:
        os.execvp("sudo", ["sudo", "python3"] + sys.argv)

    print("--- Permissions Inspector ---")
    print("(Leave blank and press Enter to exit)")

    path_input = input("\nEnter the directory or file path: ").strip()

    # 2. Graceful Exit
    if not path_input:
        print("Exiting.")
        return

    # Expand ~ or environment variables
    path = os.path.expanduser(os.path.expandvars(path_input))

    if not os.path.exists(path):
        print(f"Error: Path '{path}' does not exist.")
        return

    try:
        file_stat = os.stat(path)
        mode = file_stat.st_mode

        # 3. Robust Octal Logic
        # Using format to get the full octal, then taking the last 4 digits
        # This ensures we don't miss SetUID (4), SetGID (2), or Sticky Bit (1)
        full_octal = oct(mode)
        numeric_perms = full_octal[-4:] if len(full_octal) > 4 else full_octal[-3:]

        # Metadata
        owner_name = pwd.getpwuid(file_stat.st_uid).pw_name
        group_name = grp.getgrgid(file_stat.st_gid).gr_name
        modified_time = datetime.fromtimestamp(file_stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
        symbolic = stat.filemode(mode)

        # 4. Intelligence: Explain what the permissions actually allow
        readable = os.access(path, os.R_OK)
        writable = os.access(path, os.W_OK)
        executable = os.access(path, os.X_OK)

        print("\n" + "="*40)
        print(f"FILE: {os.path.basename(path)}")
        print(f"PATH: {path}")
        print("-" * 40)
        print(f"Permissions: {numeric_perms} ({symbolic})")
        print(f"Ownership:   {owner_name}:{group_name}")
        print(f"Modified:    {modified_time}")
        print("-" * 40)

        # Summary for new users
        print(f"Can YOU read this?     {'Yes' if readable else 'No'}")
        print(f"Can YOU write/edit?    {'Yes' if writable else 'No'}")
        print(f"Can YOU execute/enter? {'Yes' if executable else 'No'}")

        # Security Warning for Special Bits
        if len(numeric_perms) == 4 and numeric_perms[0] != '0':
            print("\nNOTE: Special bits (SUID/SGID/Sticky) are active.")

        print("="*40)

    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    check_permissions()
