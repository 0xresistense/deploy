#!/usr/bin/env bash
# Import ProtonVPN free servers into NetworkManager
# Creates NM keyfiles directly from the template
#
# Usage: ./protonvpn-import.sh [--all | --country US,NL,JP | --pick N]
#   --all        Import all free servers
#   --country    Import servers from specific countries (comma-separated)
#   --pick N     Import N servers per country (default: 2)

set -euo pipefail

SERVERS_JSON="/tmp/protonvpn_free_servers.json"
CERT_DIR="$HOME/.cert/nm-openvpn"
CA_SRC="$CERT_DIR/us-free-33.protonvpn.udp-ca.pem"
TLS_SRC="$CERT_DIR/us-free-33.protonvpn.udp-tls-crypt.pem"
NM_DIR="/etc/NetworkManager/system-connections"
TEMPLATE_CONN="us-free-33.protonvpn.udp"

if [[ ! -f "$SERVERS_JSON" ]]; then
    echo "Error: $SERVERS_JSON not found"
    exit 1
fi

# Read creds from existing connection
USERNAME=$(nmcli -s -g vpn.data connection show "$TEMPLATE_CONN" | tr ',' '\n' | grep username | sed 's/.*= //')
PASSWORD=$(nmcli -s -g vpn.secrets connection show "$TEMPLATE_CONN" | tr ',' '\n' | grep password | sed 's/.*= //')
PORTS="4569,5060,80,1194,51820"

MODE="${1:---pick}"
ARG="${2:-2}"

# Build server list via Python
SELECTED=$(python3 << PYEOF
import json, random, sys

with open("$SERVERS_JSON") as f:
    servers = json.load(f)

mode = "$MODE"
arg = "$ARG"

if mode == "--country":
    allowed = [c.strip().upper() for c in arg.split(",")]
    servers = [s for s in servers if s["name"].split("-")[0].upper() in allowed]
elif mode == "--pick":
    n = int(arg)
    by_cc = {}
    for s in servers:
        cc = s["name"].split("-")[0].upper()
        by_cc.setdefault(cc, []).append(s)
    servers = []
    for cc, srvs in sorted(by_cc.items()):
        servers.extend(random.sample(srvs, min(n, len(srvs))))
# --all: use all servers as-is

for s in sorted(servers, key=lambda x: x["name"]):
    print(f"{s['name']}|{s['ip']}|{s.get('city','')}")
PYEOF
)

if [[ -z "$SELECTED" ]]; then
    echo "No servers selected"
    exit 1
fi

EXISTING=$(nmcli -t -f NAME connection show 2>/dev/null)
ADDED=0
SKIPPED=0

while IFS='|' read -r NAME IP CITY; do
    # Build connection name: US-FREE#33 → us-free-33.protonvpn.udp
    CONN=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed 's/#/-/g').protonvpn.udp

    if echo "$EXISTING" | grep -qx "$CONN"; then
        echo "  SKIP $CONN (exists)"
        ((SKIPPED++))
        continue
    fi

    # Copy certs
    CA_DEST="$CERT_DIR/${CONN}-ca.pem"
    TLS_DEST="$CERT_DIR/${CONN}-tls-crypt.pem"
    [[ -f "$CA_DEST" ]] || cp "$CA_SRC" "$CA_DEST"
    [[ -f "$TLS_DEST" ]] || cp "$TLS_SRC" "$TLS_DEST"

    # Build remote string
    REMOTE=$(echo "$PORTS" | tr ',' '\n' | sed "s/^/${IP}:/" | paste -sd', ')

    # Generate UUID
    UUID=$(python3 -c "import uuid; print(uuid.uuid4())")

    # Write keyfile
    KEYFILE="$NM_DIR/${CONN}.nmconnection"
    sudo tee "$KEYFILE" > /dev/null << EOF
[connection]
id=$CONN
uuid=$UUID
type=vpn
autoconnect=false

[vpn]
ca=$CA_DEST
challenge-response-flags=2
cipher=AES-256-GCM
connection-type=password
dev=tun
mssfix=0
password-flags=0
remote=$REMOTE
remote-cert-tls=server
remote-random=yes
reneg-seconds=0
tls-crypt=$TLS_DEST
tunnel-mtu=1500
username=$USERNAME
service-type=org.freedesktop.NetworkManager.openvpn

[vpn-secrets]
password=$PASSWORD

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
    sudo chmod 600 "$KEYFILE"
    sudo chown root:root "$KEYFILE"

    printf "  ADD  %-40s %s\n" "$CONN" "$CITY"
    ((ADDED++))

done <<< "$SELECTED"

# Reload NM to pick up new connections
sudo nmcli connection reload

echo ""
echo "Done: $ADDED added, $SKIPPED skipped"
echo "Tray applet: click 'Refresh Servers' to see new connections"
