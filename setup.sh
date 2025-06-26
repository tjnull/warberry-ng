#!/bin/bash

# Kali Linux ARM Security Tool Setup with OPSEC & Traffic Obfuscation
# Author: Tj Null
# Date: June 26th 2025
# Version: 1.0

LOGFILE="setup.log"

# ========================
# Help Menu Function
# ========================
show_help() {
  cat <<'EOF'
┌────────────────────────────────────────────────────────────┐
│                   Warberry-ng Setup Script                 │
│                    Author: Tj Null                         │
│                   Version: 1.0 (2025-06-26)                │
└────────────────────────────────────────────────────────────┘

Description:
  This script sets up a Kali Linux ARM environment for network,
  wireless, and red team operations. It also includes optional
  OPSEC and stealth features to obfuscate system identity and 
  user activity.

Usage:
  sudo ./setup.sh [OPTIONS]

Options:
  --enable-opsec         Enable OPSEC mode:
                           - Masks Kali Linux identity
                           - Sets generic hostname
                           - Removes branding & banners
                           - Disables root history
                           - Removes visual Kali packages

  --obfuscate-traffic    Enables traffic obfuscation by:
                           - Setting global proxy variables
                           - Overriding curl, wget, pip User-Agent
                           - Mimicking Windows browser headers

  --revert-opsec         Reverts all OPSEC modifications:
                           - Restores original /etc/os-release
                           - Resets hostname to "kali"
                           - Restores /etc/issue, motd
                           - Removes traffic obfuscation variables

  --help, -h             Show this help menu and exit

Example:
  sudo ./setup.sh --enable-opsec --obfuscate-traffic
  sudo ./setup.sh --revert-opsec

Important Notes:
  • This script logs terminal sessions and all 'sudo' activity.
  • Use OPSEC mode on client machines or red team drop boxes.
  • Traffic obfuscation assumes a proxy exists at 127.0.0.1:3128
    (modify as needed).

EOF
  exit 0
}

# ========================
# Flags and Argument Parsing
# ========================
ENABLE_OPSEC=false
OBFUSCATE_TRAFFIC=false
REVERT_OPSEC=false

for arg in "$@"; do
  case $arg in
    --enable-opsec) ENABLE_OPSEC=true ;;
    --obfuscate-traffic) OBFUSCATE_TRAFFIC=true ;;
    --revert-opsec) REVERT_OPSEC=true ;;
    --help|-h) show_help ;;
    *) echo "[ERROR] Unknown option: $arg" | tee -a "$LOGFILE"; show_help ;;
  esac
done

# ========================
# Revert OPSEC if requested
# ========================
if $REVERT_OPSEC; then
  echo "[INFO] Reverting OPSEC changes..." | tee -a "$LOGFILE"

  # Restore os-release
  if [ -f /etc/os-release.bak ]; then
    mv /etc/os-release.bak /etc/os-release
    echo "[INFO] Restored /etc/os-release" | tee -a "$LOGFILE"
  else
    echo "[WARN] Backup /etc/os-release.bak not found!" | tee -a "$LOGFILE"
  fi

  # Restore hostname
  echo "kali" > /etc/hostname
  hostnamectl set-hostname kali
  echo "[INFO] Restored hostname to 'kali'" | tee -a "$LOGFILE"

  # Restore motd/issue
  echo "Kali GNU/Linux" > /etc/issue
  echo "Kali GNU/Linux" > /etc/issue.net
  echo "Welcome to Kali Linux" > /etc/motd

  # Remove traffic obfuscation
  sed -i '/^export http_proxy=/d' /etc/environment
  sed -i '/^export https_proxy=/d' /etc/environment
  sed -i '/CUSTOM_USER_AGENT/d' /etc/profile

  echo "[INFO] Removed traffic obfuscation settings" | tee -a "$LOGFILE"
  echo "[INFO] OPSEC revert completed." | tee -a "$LOGFILE"
  exit 0
fi

# ========================
# Root check
# ========================
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Please run as root" | tee -a "$LOGFILE"
  exit 1
fi

echo "[INFO] Starting Kali ARM Security Tool Setup..." | tee -a "$LOGFILE"

# ========================
# System Update & Base Tools
# ========================
echo "[INFO] Updating and upgrading system packages..." | tee -a "$LOGFILE"
apt update && apt full-upgrade -y | tee -a "$LOGFILE"

echo "[INFO] Installing base packages..." | tee -a "$LOGFILE"
apt install -y git curl wget pipx net-tools lsb-release software-properties-common obsidian tmux | tee -a "$LOGFILE"

# ========================
# Network Pentesting Tools
# ========================
echo "[INFO] Installing network pentesting tools..." | tee -a "$LOGFILE"
apt install -y nuclei responder nxc certipy-ad powercat mitm6 | tee -a "$LOGFILE"

# ========================
# Wireless Pentesting Tools
# ========================
echo "[INFO] Installing wireless pentesting tools..." | tee -a "$LOGFILE"
apt install -y kali-tools-wireless hcxtools bettercap | tee -a "$LOGFILE"

# ========================
# Red Team Tools
# ========================
echo "[INFO] Installing red team tools..." | tee -a "$LOGFILE"
apt install -y bloodhound bloodhound-ce-python enum4linux-ng nxc smbmap villain | tee -a "$LOGFILE"

# ========================
# Python Tools Install
# ========================
echo "[INFO] Installing pentesting tools with pipx..." | tee -a "$LOGFILE"
pipx install smbclient-ng

# ========================
# Timestamped Bash Prompt for all users
# ========================
echo "[INFO] Setting timestamped bash prompt for all users..." | tee -a "$LOGFILE"
if ! grep -q 'PS1="[\D{%F %T}]' /etc/bash.bashrc; then
  echo 'export PS1="[\D{%F %T}] \u@\h:\w\$ "' >> /etc/bash.bashrc
fi

# ========================
# Metasploit Timestamps
# ========================
echo "[INFO] Configuring metasploit to use timestamps..." | tee -a "$LOGFILE"
for userdir in /home/*; do
  if [ -d "$userdir" ]; then
    mkdir -p "$userdir/.msf4"
    echo "set TimestampOutput true" > "$userdir/.msf4/msfconsole.rc"
    chown -R "$(basename "$userdir")":"$(basename "$userdir")" "$userdir/.msf4"
  fi
done
mkdir -p /root/.msf4
echo "set TimestampOutput true" > /root/.msf4/msfconsole.rc
mkdir -p /etc/skel/.msf4
echo "set TimestampOutput true" > /etc/skel/.msf4/msfconsole.rc

# ========================
# Terminal Session Logging
# ========================
echo "[INFO] Enabling terminal session logging..." | tee -a "$LOGFILE"
mkdir -p /var/log/terminal_logs
chmod 733 /var/log/terminal_logs
chown root:root /var/log/terminal_logs

LOG_SCRIPT_BLOCK='
# === Terminal Logging ===
if [ -z "$UNDER_SCRIPT" ] && [ -t 1 ]; then
  LOGDIR="/var/log/terminal_logs"
  USERNAME=$(whoami)
  TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
  LOGFILE="$LOGDIR/${USERNAME}_$TIMESTAMP.log"
  export UNDER_SCRIPT=1
  exec script -q -f --append "$LOGFILE"
fi
'

if ! grep -q "UNDER_SCRIPT" /etc/profile; then
  echo "$LOG_SCRIPT_BLOCK" >> /etc/profile
fi

# ========================
# Sudo Command Logging
# ========================
echo "[INFO] Configuring sudo command logging..." | tee -a "$LOGFILE"
cat << 'EOF' > /etc/rsyslog.d/10-sudo.conf
if $programname == 'sudo' then /var/log/sudo_commands.log
& stop
EOF
touch /var/log/sudo_commands.log
chmod 600 /var/log/sudo_commands.log
chown root:root /var/log/sudo_commands.log
systemctl restart rsyslog

# ========================
# OPSEC Mode (Optional)
# ========================
if $ENABLE_OPSEC; then
  echo "[INFO] Applying OPSEC measures..." | tee -a "$LOGFILE"

  # Backup and spoof os-release
  if [ -f /etc/os-release ]; then
    cp /etc/os-release /etc/os-release.bak
    cat <<EOF > /etc/os-release
PRETTY_NAME="Debian GNU/Linux 12 (Bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (Bookworm)"
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
EOF
  fi

  # Remove login banners
  rm -f /etc/issue /etc/issue.net /etc/motd

  # Set generic hostname
  echo "linux-host" > /etc/hostname
  hostnamectl set-hostname linux-host

  # Remove Kali metapackages for visual branding
  apt purge -y kali-defaults kali-menu

  # Disable root bash history
  echo 'unset HISTFILE' >> /root/.bashrc
  rm -f /root/.bash_history
fi

# ========================
# Traffic Obfuscation (Optional)
# ========================
if $OBFUSCATE_TRAFFIC; then
  echo "[INFO] Setting up global traffic obfuscation..." | tee -a "$LOGFILE"

  # Set global proxy variables (change proxy if needed)
  cat <<EOF >> /etc/environment
export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"
EOF

  # Custom User-Agent aliases and variables
  cat <<'EOF' >> /etc/profile
# CUSTOM_USER_AGENT
export CURL_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
alias curl='curl -A "$CURL_USER_AGENT"'
alias wget='wget --user-agent="$CURL_USER_AGENT"'
alias pip='pip --proxy http://127.0.0.1:3128'
EOF
fi

# ========================
# Clean up
# ========================
echo "[INFO] Cleaning up unused packages..." | tee -a "$LOGFILE"
apt autoremove -y | tee -a "$LOGFILE"
apt clean | tee -a "$LOGFILE"

echo "[INFO] Setup completed successfully!" | tee -a "$LOGFILE"
