#!/usr/bin/env python3
import difflib
import os
import sys

# Terminal colors for better readability
RED = "\033[91m"
GREEN = "\033[92m"
CYAN = "\033[96m"
RESET = "\033[0m"

def compare_files():
    print("--- File Comparison Tool ---")
    print("(Leave blank to exit)")

    f1 = input("Path for First File:  ").strip()
    if not f1: return
    f2 = input("Path for Second File: ").strip()
    if not f2: return

    # Expand paths
    file1_path = os.path.expanduser(os.path.expandvars(f1))
    file2_path = os.path.expanduser(os.path.expandvars(f2))

    if not os.path.isfile(file1_path) or not os.path.isfile(file2_path):
        print(f"{RED}Error: One or both paths are not valid files.{RESET}")
        return

    try:
        with open(file1_path, 'r', encoding='utf-8') as f1_obj, \
             open(file2_path, 'r', encoding='utf-8') as f2_obj:
            file1_content = f1_obj.readlines()
            file2_content = f2_obj.readlines()

        # Unified diff is generally faster and cleaner for admins
        diff = difflib.unified_diff(
            file1_content, file2_content,
            fromfile=file1_path, tofile=file2_path, lineterm=''
        )

        has_diff = False
        print(f"\n{CYAN}--- Results ---{RESET}")

        for line in diff:
            has_diff = True
            if line.startswith('+'):
                print(f"{GREEN}{line}{RESET}")
            elif line.startswith('-'):
                print(f"{RED}{line}{RESET}")
            elif line.startswith('^'):
                print(f"{CYAN}{line}{RESET}")
            else:
                print(line)

        if not has_diff:
            print(f"{GREEN}The files are identical.{RESET}")

    except Exception as e:
        print(f"{RED}Error: {e}{RESET}")

if __name__ == '__main__':
    compare_files()
