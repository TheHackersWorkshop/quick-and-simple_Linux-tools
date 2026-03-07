#!/usr/bin/env python3
import subprocess
import os
import sys

def search_files():
    print("--- Deep File Finder ---")

    # 1. Automatic Elevation (Search usually needs root for /media)
    if os.geteuid() != 0:
        os.execvp("sudo", ["sudo", "python3"] + sys.argv)

    # 2. Pattern Input
    pattern = input("File pattern (e.g., 'invoice*' or '*.pdf'): ").strip()
    if not pattern:
        print("No pattern provided. Exiting.")
        return

    # 3. Directory with Expansion
    default_dir = "/media"
    dir_input = input(f"Search directory [default: {default_dir}]: ").strip()
    search_dir = os.path.expanduser(os.path.expandvars(dir_input)) if dir_input else default_dir

    if not os.path.isdir(search_dir):
        print(f"Error: '{search_dir}' is not a valid directory.")
        return

    # 4. The 'Find' Command
    # -iname: Case-insensitive search (Crucial when you 'don't know' the name)
    # -type f: Files only
    # 2>/dev/null: Hide permission denied errors
    command = ["find", search_dir, "-type f", "-iname", f"*{pattern}*", "2>/dev/null"]

    print(f"\nSearching for '{pattern}' in {search_dir}...")
    print("------------------------------------------")

    try:
        # Use Popen to stream results line-by-line
        # This is better for large drives so you don't wait forever
        proc = subprocess.Popen(" ".join(command), shell=True, stdout=subprocess.PIPE, text=True)

        found_count = 0
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            print(f"[FOUND]: {line.strip()}")
            found_count += 1

        if found_count == 0:
            print("No matches found.")
        else:
            print(f"------------------------------------------")
            print(f"Search complete. {found_count} matches found.")

    except KeyboardInterrupt:
        print("\nSearch cancelled by user.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    search_files()
