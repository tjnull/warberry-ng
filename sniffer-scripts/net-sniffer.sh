#!/bin/bash

# -------------------- Color Codes --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# -------------------- Globals --------------------
exit_confirmed=0
timestamp=$(date +%F_%H-%M-%S)
log_dir="/var/log/sniffer"
mkdir -p "$log_dir"

trap ctrl_c INT

ctrl_c() {
    if [[ $exit_confirmed -eq 0 ]]; then
        echo -e "\n${YELLOW}[!] Press CTRL+C again to stop sniffing.${NC}"
        exit_confirmed=1
        sleep 2
    else
        echo -e "\n${RED}[✘] Stopping sniffing and exiting.${NC}"
        # Kill any background sniffing processes gracefully
        pkill -P $$
        exit 0
    fi
}

show_help() {
    echo -e "${CYAN}
╔════════════════════════════════════════════════════╗
║                    NET-SNIFFER.SH HELP             ║
╚════════════════════════════════════════════════════╝${NC}

${YELLOW}Usage:${NC} sudo ./net-sniffer.sh [options]

${YELLOW}Options:${NC}
  -h, --help              Show this help menu and exit

${YELLOW}Features:${NC}
  • Choose sniffing tool: tcpdump, tshark, or scapy
  • Auto-detect default interface or specify one
  • Save capture to file (cap, pcap, or pcapng)
  • Apply capture filter (tcpdump/tshark BPF syntax)
  • Run sniffing interactively or in background (tmux)
  • Live traffic summary displayed in terminal
  • Double Ctrl+C to confirm exit

${YELLOW}Examples:${NC}
  sudo ./net-sniffer.sh           # Interactive prompts
  sudo ./net-sniffer.sh -h        # Show this help

${YELLOW}Notes:${NC}
  • Requires root (sudo).
  • Ensure tools (tcpdump, tshark, python3 with scapy) are installed.
  • Background mode uses tmux (installs if missing).
"
    exit 0
}

# Parse help option early
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# -------------------- Root Check --------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Please run this script with sudo.${NC}"
    exit 1
fi

# -------------------- Dependency Checks --------------------
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "${RED}[!] $1 is not installed. Please install it first.${NC}"
        exit 1
    fi
}

check_tool python3  # For scapy

# tmux is optional but needed for background mode
if ! command -v tmux &>/dev/null; then
    echo -e "${YELLOW}[!] tmux not found. Installing...${NC}"
    apt update && apt install -y tmux || { echo -e "${RED}[!] Failed to install tmux.${NC}"; exit 1; }
fi

# -------------------- Interface Selection --------------------
default_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
echo -e "${CYAN}[+] Default network interface detected: ${GREEN}$default_iface${NC}"
read -p "$(echo -e "${YELLOW}[?] Use this interface? (Y/n): ${NC}")" use_default

if [[ "$use_default" =~ ^[Nn]$ ]]; then
    read -p "$(echo -e "${YELLOW}Enter interface to sniff on (e.g., eth0, wlan0): ${NC}")" iface
else
    iface="$default_iface"
fi

if ! ip link show "$iface" &>/dev/null; then
    echo -e "${RED}[!] Interface '${iface}' not found.${NC}"
    exit 1
fi

# -------------------- Tool Selection --------------------
echo -e "${YELLOW}[?] Choose sniffing tool:${NC}"
echo -e "${CYAN}  1) tcpdump"
echo -e "  2) tshark"
echo -e "  3) scapy${NC}"
read -p "$(echo -e "${YELLOW}Select option [1-3]: ${NC}")" tool_choice

case $tool_choice in
    1) check_tool tcpdump ;;
    2) check_tool tshark ;;
    3) ;;
    *) echo -e "${RED}[!] Invalid option.${NC}"; exit 1 ;;
esac

# -------------------- Capture Filter --------------------
read -p "$(echo -e "${YELLOW}Enter capture filter (BPF syntax, or leave empty for none): ${NC}")" capture_filter

# -------------------- Save Capture? --------------------
read -p "$(echo -e "${YELLOW}Save capture to file? (y/N): ${NC}")" save_capture

if [[ "$save_capture" =~ ^[Yy]$ ]]; then
    # Ask for extension choice
    echo -e "${YELLOW}Choose capture file extension:${NC}"
    echo -e "${CYAN} 1) cap"
    echo -e " 2) pcap (default)"
    echo -e " 3) pcapng${NC}"
    read -p "$(echo -e "${YELLOW}Select [1-3]: ${NC}")" ext_choice

    case $ext_choice in
        1) ext="cap" ;;
        3) ext="pcapng" ;;
        *) ext="pcap" ;; # default
    esac

    capture_file="$log_dir/sniffer_${timestamp}.$ext"
    echo -e "${CYAN}[*] Captures will be saved to ${GREEN}$capture_file${NC}"
else
    capture_file=""
fi

# -------------------- Background Mode --------------------
read -p "$(echo -e "${YELLOW}Run sniffing in background (tmux)? (y/N): ${NC}")" run_bg

# -------------------- Run Functions --------------------

run_tcpdump() {
    echo -e "${GREEN}[+] Starting tcpdump on $iface with live output...${NC}"

    if [[ -n "$capture_file" ]]; then
        echo -e "${YELLOW}[!] Capturing to file and showing live traffic simultaneously...${NC}"
        echo -e "${YELLOW}[!] Press CTRL+C once to stop, twice to confirm exit.${NC}"

        # Start background capture silently writing to file
        tcpdump -i "$iface" -nn $capture_filter -w "$capture_file" &
        capture_pid=$!

        # Run tcpdump live output (no -w) in foreground to show packets
        tcpdump -i "$iface" -nn $capture_filter

        # When user stops live output, kill background writer
        kill $capture_pid 2>/dev/null
    else
        # Just live output, no saving
        tcpdump -i "$iface" -nn $capture_filter
    fi
}

run_tshark() {
    echo -e "${GREEN}[+] Starting tshark on $iface with live output...${NC}"
    cmd="tshark -i $iface"
    [[ -n "$capture_filter" ]] && cmd+=" -f \"$capture_filter\""
    if [[ -n "$capture_file" ]]; then
        cmd+=" -w $capture_file"
        # tshark outputs live by default, no special handling needed
        eval "$cmd"
    else
        eval "$cmd"
    fi
}

run_scapy() {
    echo -e "${GREEN}[+] Starting scapy sniff on $iface with live output...${NC}"

    py_script="from scapy.all import sniff
import sys
packets = []
def pkt_callback(pkt):
    print(pkt.summary())
    packets.append(pkt)
    sys.stdout.flush()

sniff(iface='$iface', filter='$capture_filter' if '$capture_filter' else None, prn=pkt_callback)
"

    if [[ -n "$capture_file" ]]; then
        py_script+="
from scapy.utils import wrpcap
wrpcap('$capture_file', packets)
"
    fi

    python3 -c "$py_script"
}

# -------------------- Background Execution --------------------
if [[ "$run_bg" =~ ^[Yy]$ ]]; then
    session_name="sniffer_$timestamp"
    echo -e "${CYAN}[*] Running in background tmux session: $session_name${NC}"

    case $tool_choice in
        1) 
            if [[ -n "$capture_file" ]]; then
                # Background capture silently writing to file
                tmux new-session -d -s "$session_name" "tcpdump -i $iface -nn $capture_filter -w $capture_file"
            else
                tmux new-session -d -s "$session_name" "tcpdump -i $iface -nn $capture_filter"
            fi
            ;;
        2) 
            if [[ -n "$capture_file" ]]; then
                tmux new-session -d -s "$session_name" "tshark -i $iface -f '$capture_filter' -w $capture_file"
            else
                tmux new-session -d -s "$session_name" "tshark -i $iface -f '$capture_filter'"
            fi
            ;;
        3) 
            # Run python scapy in tmux
            py_bg_script="/tmp/scapy_sniffer_$timestamp.py"
            echo "from scapy.all import sniff, wrpcap
packets = []
def pkt_callback(pkt):
    print(pkt.summary())
    packets.append(pkt)
sniff(iface='$iface', filter='$capture_filter' if '$capture_filter' else None, prn=pkt_callback)
if '$capture_file':
    wrpcap('$capture_file', packets)
" > "$py_bg_script"
            tmux new-session -d -s "$session_name" "python3 $py_bg_script"
            ;;
    esac

    echo -e "${GREEN}[✓] Sniffing running in background."
    echo -e "${CYAN}Attach with: tmux attach -t $session_name${NC}"
else
    # Run interactively
    case $tool_choice in
        1) run_tcpdump ;;
        2) run_tshark ;;
        3) run_scapy ;;
    esac
fi
