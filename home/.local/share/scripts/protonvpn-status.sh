#!/usr/bin/env bash
# VPN status for polybar
# Detects active ProtonVPN or NordVPN connection

active=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep ":vpn" | grep -iE 'protonvpn|nordvpn' | cut -d: -f1)

if [[ -z "$active" ]]; then
    echo "󰌗 OFF"
elif [[ "$active" == *nordvpn* ]]; then
    # "us12072.nordvpn.com.udp" → "NORD-US12072"
    short=$(echo "$active" | sed 's/\.nordvpn.*//; s/\.//g' | tr '[:lower:]' '[:upper:]')
    echo "󰌗 N-$short"
else
    # "us-free-33.protonvpn.udp" → "US-33"
    short=$(echo "$active" | sed 's/\.protonvpn.*//; s/-free//' | tr '[:lower:]' '[:upper:]')
    echo "󰌗 $short"
fi
