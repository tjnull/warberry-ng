#!/bin/bash

# Kali Linux ARM Security Tool Setup
# Author: Tj Null
# Date: June 25th 2025
# Description: Installs tools for network/wireless pentesting & red team ops

LOGFILE="setup.log"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Please run as root" | tee -a "$LOGFILE"
  exit 1
fi

echo "[INFO] Starting Kali ARM Security Tool Setup..." | tee -a "$LOGFILE"

# Update & upgrade system
echo "[INFO] Updating and upgrading system packages..." | tee -a "$LOGFILE"
apt update && apt full-upgrade -y | tee -a "$LOGFILE"

# Install base tools
echo "[INFO] Installing base packages..." | tee -a "$LOGFILE"
apt install -y git curl wget pipx net-tools lsb-release software-properties-common obsidian tmux | tee -a "$LOGFILE"

# ====================
# TOOL GROUPS
# ====================

# Network Pentesting
echo "[INFO] Installing network pentesting tools..." | tee -a "$LOGFILE"
apt install -y nuclei responder nxc certipy-ad powercat mitm6 | tee -a "$LOGFILE"

# Wireless Pentesting
echo "[INFO] Installing wireless pentesting tools..." | tee -a "$LOGFILE"
apt install -y kali-tools-wireless hcxtools bettercap | tee -a "$LOGFILE"

# Red Team Tools
echo "[INFO] Installing red team tools..." | tee -a "$LOGFILE"
apt install -y bloodhound bloodhound-ce-python enum4linux-ng nxc smbmap villain | tee -a "$LOGFILE"

# ====================
# Python Tools Install
# ====================

echo "[INFO] Installing pentesting tools with pipx..." | tee -a "$LOGFILE"

pipx install smbclient-ng


# Clean up
echo "[INFO] Cleaning up..." | tee -a "$LOGFILE"
apt autoremove -y | tee -a "$LOGFILE"
apt clean | tee -a "$LOGFILE"

echo "[INFO] Setup completed successfully!" | tee -a "$LOGFILE"

