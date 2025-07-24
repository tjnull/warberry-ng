#!/bin/bash

# ==============================================================================
# warberry-ap-builder.sh
#
# Author: Tj Null
#
# Description:
#   Sets up a systemd service to run lnxrouter as a wireless AP.
#   Features include config saving, auto download/build, and interface conflict handling.
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
DEFAULT_SSID="Warberry-NG"
DEFAULT_PASSWORD="WarberryNG1!"
DEFAULT_INTERFACE="wlan0"
DEFAULT_REPO="https://github.com/garywill/linux-router"
LR_DIR="$HOME/linux-router"
BINARY="$LR_DIR/lnxrouter"
CONFIG_FILE="$HOME/.linux-router.conf"
SERVICE_NAME="linux-router-ap"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Configurable variables
SSID=""
PASSWORD=""
AP_INTERFACE=""
REPO_URL="$DEFAULT_REPO"

### ----------- Helper Functions ----------- ###

function print_help() {
  echo -e "${BLUE}Linux Router Setup Script${NC}"
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --ssid <name>           Set AP SSID"
  echo "  --password <password>   Set AP password"
  echo "  --interface <iface>     Set wireless interface (default: wlan0)"
  echo "  --binary-path <path>    Set lnxrouter binary path"
  echo "  --repo <url>            Set Git repo to clone if binary is missing"
  echo "  -h, --help              Show this help menu"
  exit 0
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssid) SSID="$2"; shift 2 ;;
      --password) PASSWORD="$2"; shift 2 ;;
      --interface) AP_INTERFACE="$2"; shift 2 ;;
      --binary-path) BINARY="$2"; shift 2 ;;
      --repo) REPO_URL="$2"; shift 2 ;;
      -h|--help) print_help ;;
      *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
  done
}

function load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}Loading saved config from $CONFIG_FILE...${NC}"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

function save_config() {
  echo -e "${BLUE}Would you like to save these settings for next time?${NC}"
  read -rp "Save to $CONFIG_FILE? [y/N]: " save_choice
  if [[ "$save_choice" =~ ^[Yy]$ ]]; then
    cat > "$CONFIG_FILE" << EOF
SSID="$SSID"
PASSWORD="$PASSWORD"
AP_INTERFACE="$AP_INTERFACE"
BINARY="$BINARY"
EOF
    echo -e "${GREEN}Configuration saved.${NC}"
  fi
}

function validate_ssid() {
  [[ -z "$1" || "$1" =~ [[:space:]] ]] && \
    echo -e "${RED}SSID cannot be empty or contain spaces.${NC}" && return 1
  return 0
}

function validate_password() {
  [[ ${#1} -lt 8 || "$1" =~ [[:space:]] ]] && \
    echo -e "${RED}Password must be at least 8 characters with no spaces.${NC}" && return 1
  return 0
}

function ensure_binary() {
  if [[ -x "$BINARY" ]]; then return 0; fi

  echo -e "${YELLOW}Binary not found at $BINARY. Cloning repo...${NC}"
  git clone "$REPO_URL" "$LR_DIR" || {
    echo -e "${RED}Failed to clone repo.${NC}"; exit 1;
  }

  echo -e "${YELLOW}Attempting to build the binary...${NC}"
  make -C "$LR_DIR" || {
    echo -e "${RED}Build failed. Exiting.${NC}"; exit 1;
  }

  if [[ ! -x "$BINARY" ]]; then
    echo -e "${RED}Binary not found after build.${NC}"; exit 1;
  fi
}

function backup_conflicting_configs() {
  echo -e "${YELLOW}Checking for conflicts on interface: $AP_INTERFACE${NC}"
  read -rp "Back up and rename any matching config files? [y/N]: " backup_choice

  [[ ! "$backup_choice" =~ ^[Yy]$ ]] && {
    echo -e "${YELLOW}Skipping backup. Make sure $AP_INTERFACE isn't being managed by another service.${NC}"
    return
  }

  # --- NetworkManager ---
  NM_DIR="/etc/NetworkManager/system-connections"
  if sudo test -d "$NM_DIR"; then
    echo -e "${BLUE}Scanning NetworkManager configs...${NC}"
    for file in "$NM_DIR"/*; do
      [[ -f "$file" ]] || continue
      if sudo grep -q "$AP_INTERFACE" "$file"; then
        echo -e "${YELLOW}Backing up: $file → $file.bak${NC}"
        sudo mv "$file" "$file.bak"
      fi
    done
  fi

  # --- Netplan (only top-level /etc/netplan/*.yaml) ---
  NETPLAN_DIR="/etc/netplan"
  if sudo test -d "$NETPLAN_DIR"; then
    echo -e "${BLUE}Scanning Netplan configs...${NC}"
    for file in "$NETPLAN_DIR"/*.yaml; do
      [[ -f "$file" ]] || continue
      if sudo grep -q "$AP_INTERFACE" "$file"; then
        echo -e "${YELLOW}Backing up: $file → $file.bak${NC}"
        sudo mv "$file" "$file.bak"
      fi
    done
  fi
}



function prompt_reboot() {
  echo -ne "${YELLOW}Setup complete. Reboot recommended.${NC}\n"
  read -rp "Reboot now? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && sudo reboot || echo "Remember to reboot later."
}

### ----------- Main Setup Function ----------- ###

function setup_service() {
  echo -e "${BLUE}--- Linux Router AP Setup ---${NC}"

  load_config

  while true; do
    read -rp "Enter SSID [${SSID:-$DEFAULT_SSID}]: " input
    SSID="${input:-${SSID:-$DEFAULT_SSID}}"
    validate_ssid "$SSID" && break
  done

  while true; do
    read -rsp "Enter password [${PASSWORD:-$DEFAULT_PASSWORD}]: " input
    echo
    PASSWORD="${input:-${PASSWORD:-$DEFAULT_PASSWORD}}"
    validate_password "$PASSWORD" && break
  done

  read -rp "Enter wireless interface [${AP_INTERFACE:-$DEFAULT_INTERFACE}]: " input
  AP_INTERFACE="${input:-${AP_INTERFACE:-$DEFAULT_INTERFACE}}"

  read -rp "Enter path to lnxrouter binary [${BINARY:-$LR_DIR/lnxrouter}]: " input
  BINARY="${input:-${BINARY:-$LR_DIR/lnxrouter}}"

  echo -e "${BLUE}Configuration:${NC}"
  echo -e "  SSID: ${GREEN}$SSID${NC}"
  echo -e "  Password: ${GREEN}$PASSWORD${NC}"
  echo -e "  Interface: ${GREEN}$AP_INTERFACE${NC}"
  echo -e "  Binary: ${GREEN}$BINARY${NC}"

  backup_conflicting_configs
  ensure_binary

  echo -e "${BLUE}Creating systemd service file...${NC}"
  sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Linux Router Access Point Service
After=network.target

[Service]
Type=simple
ExecStart=$BINARY --ap $AP_INTERFACE $SSID -p $PASSWORD
Restart=on-failure
RestartSec=5s
WorkingDirectory=$(dirname "$BINARY")

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now "$SERVICE_NAME"
 

  sleep 2
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}Service is running.${NC}"
  else
    echo -e "${RED}Service failed to start. Use 'sudo systemctl status $SERVICE_NAME'.${NC}"
  fi

  save_config
  prompt_reboot
}

function cleanup_service() {
  echo -e "${YELLOW}Stopping and removing service...${NC}"
  sudo systemctl stop "$SERVICE_NAME" 2>/dev/null
  sudo systemctl disable "$SERVICE_NAME" 2>/dev/null

  if [[ -f "$SERVICE_FILE" ]]; then
    sudo rm -f "$SERVICE_FILE"
  fi

  sudo systemctl daemon-reload
  echo -e "${GREEN}Cleanup complete.${NC}"
}

### ----------- Menu and Execution ----------- ###

if [[ $# -eq 0 ]]; then
  echo -e "${BLUE}Choose an option:${NC}"
  echo "1) Setup linux-router AP service"
  echo "2) Cleanup (remove service)"
  echo "3) Exit"
  read -rp "Enter choice [1-3]: " choice
  case "$choice" in
    1) setup_service ;;
    2) cleanup_service ;;
    3) echo "Exiting." ; exit 0 ;;
    *) echo -e "${RED}Invalid option.${NC}" ; exit 1 ;;
  esac
else
  parse_args "$@"
  setup_service
fi
