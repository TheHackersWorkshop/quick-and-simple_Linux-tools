#!/usr/bin/env python3
import os

def combine_files():
    print("--- File Merger Tool ---")
    print("(Leave blank to exit)")

    # 1. Input with expansion
    source_input = input("Enter source directory: ").strip()
    if not source_input:
        print("Exiting.")
        return

    source_dir = os.path.expanduser(os.path.expandvars(source_input))

    if not os.path.isdir(source_dir):
        print(f"Error: '{source_dir}' is not a valid directory.")
        return

    # 2. Filter and avoid recursion
    output_filename = 'combined_list.txt'
    files = sorted([
        f for f in os.listdir(source_dir)
        if os.path.isfile(os.path.join(source_dir, f))
        and f != output_filename  # Don't merge the output into itself!
    ])

    if not files:
        print("No files found to combine.")
        return

    # 3. Preview for the user
    print(f"\nFound {len(files)} files. (e.g., {files[0]} ... {files[-1]})")
    confirm = input(f"Combine these into {output_filename}? (y/n): ")
    if confirm.lower() != 'y':
        print("Aborted.")
        return

    # 4. Process with error handling for binary files
    output_path = os.path.join(os.getcwd(), output_filename)
    combined_count = 0
    error_count = 0

    with open(output_path, 'w', encoding='utf-8') as outfile:
        for filename in files:
            filepath = os.path.join(source_dir, filename)
            try:
                with open(filepath, 'r', encoding='utf-8') as infile:
                    content = infile.read()
                    outfile.write(f"\n{'#'*40}\n")
                    outfile.write(f"# FILE: {filename}\n")
                    outfile.write(f"{'#'*40}\n\n")
                    outfile.write(content)
                    outfile.write("\n")
                    combined_count += 1
            except (UnicodeDecodeError, PermissionError):
                # Skip binary files or locked files
                error_count += 1
                continue

    print(f"\nSuccess! {combined_count} files combined into '{output_filename}'.")
    if error_count > 0:
        print(f"Note: {error_count} file(s) were skipped (likely binary or restricted).")

if __name__ == "__main__":
    combine_files()
