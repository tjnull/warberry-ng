#!/bin/bash

# =====================[ Linux Wireless Connect Script GUI ]=====================
# Version: 1.0
# Author: Tj Null
# Purpose:
#   - Scan available wireless interfaces and networks
#   - Connect using WPA supplicant and obtain IP via DHCP or static assignment
#   - Optionally disconnect cleanly
#   - Retry/reconnect option on failure
#   - GUI prompts via zenity
#   - Logging of all actions and outputs
# ==============================================================================

LOGFILE="/var/log/wifi-connect-script.log"
exec &> >(tee -a "$LOGFILE")

# Color definitions (for CLI fallback)
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

function show_help() {
  echo -e "${CYAN}"
  echo "============================================================================="
  echo "            Linux Wireless Connect Script GUI - v1.0"
  echo "=============================================================================${RESET}"
  echo -e "Usage:"
  echo -e "  sudo $0                         - Connect via GUI"
  echo -e "  sudo $0 --disconnect            - Cleanly disconnect Wi‑Fi"
  echo -e "  $0 -h | --help                  - Show this help"
  echo -e "  $0 --version                   - Show version info"
  echo
  echo -e "Features:"
  echo -e "  ✓ retry/reconnect on failure"
  echo -e "  ✓ GUI prompts via zenity (larger windows)"
  echo -e "  ✓ Full scan listing including hidden and duplicate networks"
  echo -e "  ✓ Logging to $LOGFILE"
  echo
  exit 0
}

# Show version info
if [[ "$1" == "--version" ]]; then
  echo -e "${CYAN}[*] Linux Wireless Connect Script v1.0${RESET}"
  exit 0
fi

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[!] Run with sudo or as root.${RESET}"
  exit 1
fi

# Disconnect Wi-Fi interfaces function
function disconnect_wifi() {
  mapfile -t IFACES < <(iw dev | awk '$1=="Interface"{print $2}' | sort)
  [[ ${#IFACES[@]} -eq 0 ]] && { echo -e "${RED}[!] No wireless interfaces found.${RESET}"; exit 1; }

  # Use zenity checklist to pick interfaces to disconnect
  choice=$(zenity --list --height=400 --width=600 --text="Select interface(s) to disconnect:" \
    --checklist --column="Kill?" --column="Interface" \
    $(for i in "${IFACES[@]}"; do echo "FALSE" "$i"; done))
  [[ -z "$choice" ]] && exit 0

  # Disconnect selected interfaces
  for IF in $choice; do
    pkill -f "wpa_supplicant.*$IF" 2>/dev/null
    pkill -f "dhclient.*$IF" 2>/dev/null
    ip link set "$IF" down
    ip addr flush dev "$IF"
    ip link set "$IF" up
  done

  zenity --info --text="Disconnected interface(s): $choice"
  exit 0
}

# Handle CLI args
if [[ "$1" =~ ^(-h|--help)$ ]]; then show_help
elif [[ "$1" == "--disconnect" ]]; then disconnect_wifi
fi

function connect_flow() {
  # List wireless interfaces
  mapfile -t IFACES < <(iw dev | awk '$1=="Interface"{print $2}' | sort)
  if [[ ${#IFACES[@]} -eq 0 ]]; then
    zenity --error --text="No wireless interfaces found."
    exit 1
  fi

  IFACE=$(zenity --list --height=300 --width=600 --text="Select wireless interface:" \
    --radiolist --column="Pick" --column="Interface" \
    $(for i in "${IFACES[@]}"; do echo "FALSE" "$i"; done))
  [[ -z "$IFACE" ]] && exit 0

  # Prepare interface
  rfkill unblock wifi
  ip link set "$IFACE" up
  sleep 1

  # Scan networks (store full output)
  SCAN_OUTPUT=$(iwlist "$IFACE" scan 2>/dev/null)
  if [[ $? -ne 0 || -z "$SCAN_OUTPUT" ]]; then
    zenity --error --text="Failed to scan networks or no networks found."
    exit 1
  fi

  # Extract ESSIDs, include duplicates and mark hidden as <hidden>
  mapfile -t SSIDS < <(echo "$SCAN_OUTPUT" | awk -F ':' '/ESSID/ {gsub(/"/,"",$2); if(length($2)==0) print "<hidden>"; else print $2}')
  if [[ ${#SSIDS[@]} -eq 0 ]]; then
    zenity --error --text="No wireless networks found."
    exit 1
  fi

  # Build zenity list args with all SSIDs including duplicates
  ZENITY_LIST=()
  for ssid in "${SSIDS[@]}"; do
    ZENITY_LIST+=("FALSE" "$ssid")
  done

  # Prompt user to select network (larger window)
  SSID=$(zenity --list --text="Select Wi‑Fi network:" --radiolist --width=700 --height=400 --column="Pick" --column="SSID" "${ZENITY_LIST[@]}")
  [[ -z "$SSID" ]] && exit 0

  # If <hidden> selected, ask for actual SSID
  if [[ "$SSID" == "<hidden>" ]]; then
    SSID=$(zenity --entry --text="Enter the hidden network's SSID:")
    [[ -z "$SSID" ]] && exit 0
  fi

  # Hidden network?
  HIDDEN=$(zenity --question --text="Is '$SSID' hidden?" && echo yes || echo no)

  # Password needed?
  NEED_PASS=$(zenity --question --text="Does '$SSID' require a password?" && echo yes || echo no)

  CONFIG="/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf"
  if [[ "$NEED_PASS" == "yes" ]]; then
    PASS=$(zenity --password --text="Enter password for '$SSID':")
    if [[ -z "$PASS" ]]; then
      zenity --error --text="No password entered, aborting."
      exit 1
    fi
    wpa_passphrase "$SSID" "$PASS" > "$CONFIG"
    [[ "$HIDDEN" == "yes" ]] && echo "scan_ssid=1" >> "$CONFIG"
  else
    # Open network
    cat <<EOF > "$CONFIG"
network={
  ssid="$SSID"
  scan_ssid=1
  key_mgmt=NONE
}
EOF
  fi

  # Clean previous connections & reset interface
  pkill -f "wpa_supplicant.*$IFACE" 2>/dev/null
  pkill -f "dhclient.*$IFACE" 2>/dev/null
  ip link set "$IFACE" down
  ip addr flush dev "$IFACE"
  ip link set "$IFACE" up
  rfkill unblock wlan

  # Start WPA supplicant
  wpa_supplicant -B -i "$IFACE" -c "$CONFIG" -D nl80211,wext

  # DHCP or static IP?
  USE_DHCP=$(zenity --question --text="Use DHCP for '$SSID'?" && echo yes || echo no)
  if [[ "$USE_DHCP" == "yes" ]]; then
    dhclient "$IFACE"
  else
    STATIC_IP=$(zenity --entry --text="Enter static IP (e.g. 192.168.1.100/24):")
    GW=$(zenity --entry --text="Enter gateway (e.g. 192.168.1.1):")
    DNS=$(zenity --entry --text="Enter DNS server (e.g. 8.8.8.8):")
    ip addr add "$STATIC_IP" dev "$IFACE"
    ip route add default via "$GW"
    echo "nameserver $DNS" > /etc/resolv.conf
  fi

  # Confirm connection by IP address
  IP=$(ip addr show "$IFACE" | awk '/inet / {print $2}' | head -n1)
  if [[ -n "$IP" ]]; then
    zenity --info --text="Connected to '$SSID' with IP: $IP"
  else
    zenity --error --text="Connection failed. No IP assigned."
    RETRY=$(zenity --question --text="Retry connection?" && echo yes || echo no)
    [[ "$RETRY" == "yes" ]] && connect_flow || exit 1
  fi

  # Prompt to disconnect
  DISC=$(zenity --question --text="Disconnect from '$SSID' now?" && echo yes || echo no)
  if [[ "$DISC" == "yes" ]]; then
    disconnect_wifi
  else
    zenity --info --text="Connection maintained. Use --disconnect option later to disconnect."
  fi
}

connect_flow
exit 0
