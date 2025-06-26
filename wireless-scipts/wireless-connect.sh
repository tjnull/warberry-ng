#!/bin/bash

# =====================[ Linux Wireless Connect Script ]=====================
# Version: 1.0
# Author: Tj Null
# Purpose:
#   - Scan available wireless interfaces and networks
#   - Connect using WPA supplicant and obtain IP via DHCP or static assignment
#   - Optionally disconnect cleanly
# ==============================================================================

# =========[ Color Definitions ]=========
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# =========[ Help Menu ]=========
function show_help() {
  echo -e "${CYAN}"
  echo "============================================================================="
  echo "                     Linux Wireless Connect Script - v1.0"
  echo "=============================================================================${RESET}"
  echo
  echo -e "Usage:"
  echo -e "  ${YELLOW}sudo $0${RESET}                     - Scan and connect to a wireless network"
  echo -e "  ${YELLOW}sudo $0 --disconnect${RESET}        - Cleanly disconnect from the current network"
  echo -e "  ${YELLOW}$0 -h | --help${RESET}              - Show this help message and exit"
  echo -e "  ${YELLOW}$0 --version${RESET}                - Show script version and exit"
  echo
  echo -e "Description:"
  echo -e "  This script assists in managing Wi-Fi connections on Kali Linux systems by utilizing WPA_Supplicant."
  echo -e "  It provides an interactive interface for:"
  echo -e "    ${GREEN}✓${RESET} Scanning for wireless interfaces and networks"
  echo -e "    ${GREEN}✓${RESET} Connecting to WPA/WPA2 or open networks"
  echo -e "    ${GREEN}✓${RESET} Assigning IP addresses via DHCP or static configuration"
  echo -e "    ${GREEN}✓${RESET} Clean disconnection and interface reset"
  echo
  echo -e "Examples:"
  echo -e "  ${YELLOW}sudo $0${RESET}"
  echo -e "    - Start the connection flow: select interface, choose network, configure IP"
  echo
  echo -e "  ${YELLOW}sudo $0 --disconnect${RESET}"
  echo -e "    - Disconnect selected or all interfaces, kill processes, flush IP"
  echo
  echo -e "Notes:"
  echo -e "  ${RED}*${RESET} This script must be run with ${YELLOW}sudo${RESET} or as ${YELLOW}root${RESET}."
  echo -e "  ${RED}*${RESET} Ensure ${YELLOW}wpa_supplicant${RESET}, ${YELLOW}dhclient${RESET}, and ${YELLOW}iw${RESET} are installed."
  echo
  echo -e "${CYAN}=============================================================================${RESET}"
  exit 0
}

# =========[ Version Info ]=========
if [[ "$1" == "--version" ]]; then
  echo -e "${CYAN}[*] Kali Linux Wireless Connect Script v1.0${RESET}"
  exit 0
fi

# =========[ Ensure Sudo ]=========
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] This script must be run with sudo or as root.${RESET}"
  exit 1
fi

# =========[ Disconnect Option ]=========
function disconnect_wifi() {
  echo -e "${CYAN}[*] Available wireless interfaces:${RESET}"
  mapfile -t IFACES < <(iw dev | awk '$1=="Interface"{print $2}' | sort)

  if [ ${#IFACES[@]} -eq 0 ]; then
    echo -e "${RED}[!] No wireless interfaces found.${RESET}"
    exit 1
  fi

  for i in "${!IFACES[@]}"; do
    echo "    [$i] ${IFACES[$i]}"
  done
  echo "    [a] All interfaces"

  read -p "[?] Select interface number to disconnect (or 'a' for all): " CHOICE

  if [[ "$CHOICE" == "a" || "$CHOICE" == "A" ]]; then
    TARGET_IFACES=("${IFACES[@]}")
  elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [[ "$CHOICE" -lt ${#IFACES[@]} ]]; then
    TARGET_IFACES=("${IFACES[$CHOICE]}")
  else
    echo -e "${RED}[!] Invalid selection. Exiting.${RESET}"
    exit 1
  fi

  for IFACE in "${TARGET_IFACES[@]}"; do
    echo -e "${CYAN}[*] Disconnecting interface: $IFACE${RESET}"
    pkill -f "wpa_supplicant.*$IFACE" 2>/dev/null
    pkill -f "dhclient.*$IFACE" 2>/dev/null
    ip link set "$IFACE" down
    ip addr flush dev "$IFACE"
    ip link set "$IFACE" up
  done

  echo -e "${GREEN}[+] Disconnection completed.${RESET}"
  exit 0
}

# =========[ Argument Handling ]=========
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
elif [[ "$1" == "--disconnect" ]]; then
  disconnect_wifi
fi

# =========[ Detect Wireless Interfaces ]=========
WIRELESS_IFACES=($(iw dev | awk '$1=="Interface"{print $2}' | sort))
if [ ${#WIRELESS_IFACES[@]} -eq 0 ]; then
  echo -e "${RED}[!] No wireless interfaces found.${RESET}"
  exit 1
fi

echo -e "${CYAN}[*] Wireless interfaces detected:${RESET}"
for i in "${!WIRELESS_IFACES[@]}"; do
  echo "    [$i] ${WIRELESS_IFACES[$i]}"
done

read -p "[?] Select the interface number to use: " IFACE_INDEX
IFACE="${WIRELESS_IFACES[$IFACE_INDEX]}"
if [ -z "$IFACE" ]; then
  echo -e "${RED}[!] Invalid selection. Exiting.${RESET}"
  exit 1
fi

# =========[ Prepare Interface & Scan for Networks ]=========
echo -e "${CYAN}[*] Bringing interface ${IFACE} up and unblocking RF...${RESET}"
rfkill unblock wifi
ip link set "$IFACE" up
sleep 1

echo -e "${CYAN}[*] Scanning for wireless networks on ${IFACE}...${RESET}"
SCAN_OUTPUT=$(iwlist "$IFACE" scan 2>&1)
if echo "$SCAN_OUTPUT" | grep -q "Network is down"; then
  echo -e "${RED}[!] Interface ${IFACE} is down or unsupported.${RESET}"
  exit 1
fi

echo "$SCAN_OUTPUT" | grep 'ESSID' | sed 's/.*ESSID:"\(.*\)"/\1/' | sort -u > /tmp/wifi_networks.txt
if [ ! -s /tmp/wifi_networks.txt ]; then
  echo -e "${RED}[!] No networks found. Exiting.${RESET}"
  exit 1
fi

mapfile -t SSIDS < /tmp/wifi_networks.txt
echo -e "${CYAN}[*] Available networks:${RESET}"
for i in "${!SSIDS[@]}"; do
  echo "    [$i] ${SSIDS[$i]}"
done

read -p "[?] Select network number to connect: " SSID_INDEX
SSID="${SSIDS[$SSID_INDEX]}"
if [ -z "$SSID" ]; then
  echo -e "${RED}[!] Invalid selection. Exiting.${RESET}"
  exit 1
fi

read -p "[?] Is the network hidden (not broadcasted)? (y/n): " IS_HIDDEN
read -p "[?] Does '$SSID' require a password? (y/n): " NEED_PASS
CONFIG_FILE="/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf"

if [[ "$NEED_PASS" =~ ^[Yy]$ ]]; then
  read -s -p "[?] Enter password for '$SSID': " SSID_PASS
  echo
  wpa_passphrase "$SSID" "$SSID_PASS" > "$CONFIG_FILE"
  if [[ "$IS_HIDDEN" =~ ^[Yy]$ ]]; then
    echo "scan_ssid=1" >> "$CONFIG_FILE"
  fi
else
  echo -e "network={\n\tssid=\"$SSID\"\n\tscan_ssid=1\n\tkey_mgmt=NONE\n}" > "$CONFIG_FILE"
fi

# =========[ Clean Interface State ]=========
echo -e "${CYAN}[*] Killing previous connections and flushing state...${RESET}"
pkill -f "wpa_supplicant.*$IFACE" 2>/dev/null
pkill -f "dhclient.*$IFACE" 2>/dev/null
ip link set "$IFACE" down
ip addr flush dev "$IFACE"
ip link set "$IFACE" up
rfkill unblock wlan

# =========[ Start WPA Supplicant ]=========
echo -e "${CYAN}[*] Starting WPA Supplicant on $IFACE...${RESET}"
wpa_supplicant -B -i "$IFACE" -c "$CONFIG_FILE" -D nl80211,wext

# =========[ DHCP or Static IP ]=========
read -p "[?] Use DHCP to obtain IP? (y/n): " USE_DHCP

if [[ "$USE_DHCP" =~ ^[Yy]$ ]]; then
  echo -e "${CYAN}[*] Requesting IP address via DHCP...${RESET}"
  dhclient "$IFACE"
else
  read -p "[?] Enter static IP address (e.g. 192.168.1.100/24): " STATIC_IP
  read -p "[?] Enter default gateway (e.g. 192.168.1.1): " GATEWAY
  read -p "[?] Enter DNS server (e.g. 8.8.8.8): " DNS

  echo -e "${CYAN}[*] Applying static network configuration...${RESET}"
  ip addr add "$STATIC_IP" dev "$IFACE"
  ip route add default via "$GATEWAY"
  echo "nameserver $DNS" > /etc/resolv.conf
fi

# =========[ Confirm Connection ]=========
IP=$(ip addr show "$IFACE" | awk '/inet / {print $2}' | head -n1)
if [ -n "$IP" ]; then
  echo -e "${GREEN}[+] Connected to '$SSID' with IP: $IP${RESET}"
else
  echo -e "${RED}[!] No IP address assigned. Check configuration.${RESET}"
fi

# =========[ Prompt to Disconnect ]=========
read -p "[?] Do you want to disconnect from '$SSID'? (y/n): " DISC
if [[ "$DISC" =~ ^[Yy]$ ]]; then
  disconnect_wifi
else
  echo -e "${GREEN}[+] Connection maintained. Use --disconnect later to cleanly disconnect.${RESET}"
fi

exit 0
