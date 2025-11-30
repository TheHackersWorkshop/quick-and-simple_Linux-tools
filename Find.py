import subprocess

def search_files():
    # Prompt the user for the search pattern
    file_pattern = input("Enter the file pattern to search for (e.g., '*.sh'): ")

    # Prompt the user for the directory to search (default to /media)
    directory = input("Enter the directory to search (default: /media): ") or "/media"

    # List of directories to exclude (pseudo-filesystems, runtime mounts)
    exclude_dirs = ["/proc", "/sys", "/run", "/dev"]

    # Build the exclude part of the find command
    exclude_expr = " ".join([f"-path {d} -prune -o" for d in exclude_dirs])

    # Complete find command
    command = f"sudo find {directory} {exclude_expr} -type f -name \"{file_pattern}\" -print"

    try:
        # Use Popen to stream output instead of waiting for the full command
        with subprocess.Popen(command, shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
            for line in proc.stdout:
                print(line.strip())
            stderr_output = proc.stderr.read()
            if stderr_output:
                print("Some errors occurred during search (ignored):")
                print(stderr_output.strip())
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

# Run the function
search_files()
