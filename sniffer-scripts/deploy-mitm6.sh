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
╔════════════════════════════════════════════╗
║           DEPLOY-MITM6.SH HELP MENU        ║
╚════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Usage:${NC} sudo ./deploy-mitm6.sh [options]

${YELLOW}Options:${NC}
  ${GREEN}-h, --help${NC}           Show this help message and exit.

${YELLOW}Features:${NC}
  ${GREEN}• Interface Detection${NC}  Detects default network interface (can override).
  ${GREEN}• Run Modes${NC}            Run mitm6 in Foreground, Background (tmux), or Boot-time (/etc/rc.local).
  ${GREEN}• Auto Clean Logs${NC}      Optional cleanup of old log files.
  ${GREEN}• Safe Exit${NC}            Double CTRL+C to confirm termination.
  ${GREEN}• Color Coded UI${NC}       Easy to read output with clear status indicators.

${YELLOW}Logging:${NC}
  Logs saved to: ${CYAN}/var/log/mitm6/mitm6_<timestamp>.log${NC}

${YELLOW}Examples:${NC}
  ${CYAN}sudo ./deploy-mitm6.sh${NC}          Run interactively
  ${CYAN}./deploy-mitm6.sh -h${NC}             Show this help menu

${YELLOW}Notes:${NC}
  • Requires root (sudo).
  • Assumes mitm6 is installed and available in PATH.
  • Auto-start uses /etc/rc.local (ensure system supports it).

${GREEN}Capture all of the IPv6 things!${NC}
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
log_dir="/var/log/mitm6"
log_file="$log_dir/mitm6_$timestamp.log"

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
if ! command -v mitm6 &>/dev/null; then
    echo -e "${RED}[!] mitm6 not found. Please install it first.${NC}"
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
echo -e "${YELLOW}[?] Run mitm6 in:${NC}"
echo -e "${CYAN}    1) Foreground"
echo -e "    2) Background (tmux)"
echo -e "    3) Add to boot (startup)${NC}"
read -p "$(echo -e "${YELLOW}Select option [1-3]: ${NC}")" mode

# -------------------- mitm6 Function --------------------
run_mitm6() {
    echo -e "${GREEN}[+] Starting mitm6 on interface: $iface${NC}"
    echo -e "${CYAN}[*] Logging to: $log_file${NC}"
    mitm6 -i "$iface" | tee "$log_file"
}

# -------------------- Add to Startup --------------------
add_to_startup() {
    echo -e "${GREEN}[+] Configuring mitm6 to run at boot...${NC}"
    cp "$0" /usr/local/bin/deploy-mitm6.sh
    chmod +x /usr/local/bin/deploy-mitm6.sh

    if [[ ! -f /etc/rc.local ]]; then
        echo -e "${YELLOW}[/etc/rc.local] not found. Creating it...${NC}"
        echo -e "#!/bin/bash\nbash /usr/local/bin/deploy-mitm6.sh &\nexit 0" > /etc/rc.local
        chmod +x /etc/rc.local
        echo -e "${GREEN}[✓] /etc/rc.local created and startup configured.${NC}"
    else
        if ! grep -q "deploy-mitm6.sh" /etc/rc.local 2>/dev/null; then
            sed -i -e '$i bash /usr/local/bin/deploy-mitm6.sh &\n' /etc/rc.local
            echo -e "${GREEN}[✓] Startup command appended to /etc/rc.local.${NC}"
        else
            echo -e "${YELLOW}[!] mitm6 startup already configured in /etc/rc.local.${NC}"
        fi
    fi
}

# -------------------- Run Selection --------------------
if [[ "$mode" == "2" ]]; then
    session_name="mitm6_$timestamp"
    echo -e "${CYAN}[*] Launching in background (tmux session: $session_name)${NC}"
    tmux new-session -d -s "$session_name" "mitm6 -i $iface | tee $log_file"
    echo -e "${GREEN}[✓] Running in tmux session: $session_name${NC}"
    echo -e "${CYAN}[*] Use: tmux attach -t $session_name${NC}"
elif [[ "$mode" == "3" ]]; then
    add_to_startup
else
    run_mitm6
fi

# -------------------- Auto-Clean Feature --------------------
echo -e "${YELLOW}[?] Auto-clean old logs? (y/N): ${NC}"
read clean_choice
if [[ "$clean_choice" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "${YELLOW}[?] Delete files older than how many days? (e.g., 3): ${NC}")" days_old
    days_old=${days_old:-3}

    echo -e "${CYAN}[*] Cleaning logs older than $days_old days...${NC}"
    find "$log_dir" -type f -name "*.log" -mtime +$days_old -exec rm -f {} \; && \
    echo -e "${GREEN}[✓] Old log files removed.${NC}"
else
    echo -e "${CYAN}[*] Skipping cleanup.${NC}"
fi
