#!/usr/bin/env python3
import os
import subprocess
import threading
import sys
from datetime import datetime
from rich.console import Console
from rich.table import Table
from scapy.all import rdpcap
import shutil

console = Console()
CAPTURE_DIR = "/var/log/captures" # Standardize to a system log path

# 1. Automatic Elevation
if os.geteuid() != 0:
    console.print("[yellow]Elevating to root for packet capture...[/yellow]")
    os.execvp("sudo", ["sudo", "python3"] + sys.argv)

os.makedirs(CAPTURE_DIR, exist_ok=True)

def list_interfaces():
    # 'tcpdump -D' lists interfaces. We'll parse it cleanly.
    result = subprocess.run(['tcpdump', '-D'], capture_output=True, text=True)
    interfaces = result.stdout.strip().split('\n')
    interface_map = {}

    table = Table(title="Available Interfaces")
    table.add_column("ID", style="cyan")
    table.add_column("Interface Name")

    for idx, line in enumerate(interfaces, 1):
        name = line.split('.')[1].strip().split(' ')[0]
        table.add_row(str(idx), name)
        interface_map[str(idx)] = name

    console.print(table)
    return interface_map

def capture_packets():
    iface_map = list_interfaces()
    choice = input("\nSelect interface ID (Enter to cancel): ").strip()
    if not choice or choice not in iface_map: return

    iface = iface_map[choice]
    bpf = input("BPF Filter (e.g., 'port 80' or blank): ").strip()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    file_path = os.path.join(CAPTURE_DIR, f"cap_{iface}_{timestamp}.pcap")

    # Build the command
    cmd = ["tcpdump", "-i", iface, "-w", file_path, "-v"]
    if bpf:
        cmd.extend(bpf.split())

    console.print(f"\n[bold green]Starting capture on {iface}...[/bold green]")
    console.print(f"Saving to: {file_path}")

    # 2. Targeted Process Handling
    # Use Popen so we can kill JUST this specific process later
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        input("\n[bold yellow]>>> Press Enter to STOP CAPTURE <<<[/bold yellow]\n")
    finally:
        proc.terminate() # Send SIGTERM
        proc.wait()      # Ensure it closes the file properly
        console.print(f"\n[green]Capture saved. ({os.path.getsize(file_path)} bytes)[/green]")

def analyze_pcap():
    files = sorted([f for f in os.listdir(CAPTURE_DIR) if f.endswith('.pcap')])
    if not files:
        console.print("[red]No PCAP files found in /var/log/captures[/red]")
        return

    # Select File
    table = Table(title="Saved Captures")
    table.add_column("#")
    table.add_column("Filename")
    for idx, f in enumerate(files, 1):
        table.add_row(str(idx), f)
    console.print(table)

    choice = input("Select file # to analyze: ").strip()
    if not choice.isdigit() or not (0 < int(choice) <= len(files)): return

    path = os.path.join(CAPTURE_DIR, files[int(choice)-1])

    console.print("[cyan]Loading packets (this may take a moment)...[/cyan]")
    try:
        packets = rdpcap(path)

        # 3. Enhanced Summary logic
        proto_summary = {}
        for pkt in packets:
            # Get the highest layer protocol name
            p = pkt.lastlayer().name
            proto_summary[p] = proto_summary.get(p, 0) + 1

        res_table = Table(title=f"Analysis: {files[int(choice)-1]}")
        res_table.add_column("Protocol")
        res_table.add_column("Packets", justify="right")
        for proto, count in sorted(proto_summary.items(), key=lambda x: x[1], reverse=True):
            res_table.add_row(proto, str(count))
        console.print(res_table)
    except Exception as e:
        console.print(f"[red]Scapy Error: {e}[/red]")

# ... [Manage Logs function stays similar, just update CAPTURE_DIR] ...

if __name__ == "__main__":
    # Main menu logic
    while True:
        console.print("\n[bold blue]TCPDUMP Admin Tool[/bold blue]")
        console.print("1. List Ifaces  2. Start Cap  3. Analyze  4. Manage  5. Exit")
        c = input("Choice: ").strip()
        if c == '1': list_interfaces()
        elif c == '2': capture_packets()
        elif c == '3': analyze_pcap()
        elif c == '5': break
