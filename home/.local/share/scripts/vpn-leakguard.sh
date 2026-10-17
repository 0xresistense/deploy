#!/bin/bash
# /etc/NetworkManager/dispatcher.d/99-vpn-leakguard
#
# VPN Leak Protection for ProtonVPN on Void Linux
# Handles: DNS leaks, IPv6 leaks, kill switch (iptables)
# Activates on vpn-up, cleanly reverts on vpn-down.
# Cleans up stale state on physical interface up (reboot safety).

INTERFACE="$1"
ACTION="$2"

STATE_DIR="/var/run/vpn-leakguard"
CHAIN="VPN_LEAKGUARD"
MARKER="# vpn-leakguard: VPN-only DNS"
RESOLV="/etc/resolv.conf"
RESOLV_DEFAULT_TARGET="/run/NetworkManager/resolv.conf"

log() { logger -t vpn-leakguard "$@"; }

get_vpn_dns() {
    # Try nmcli on the VPN interface first
    local dns
    dns=$(nmcli -t -f IP4.DNS device show "$INTERFACE" 2>/dev/null | cut -d: -f2 | head -1)
    if [[ -n "$dns" ]]; then
        echo "$dns"
        return
    fi
    # Fallback: VPN gateway (ProtonVPN runs DNS on its gateway)
    dns=$(nmcli -t -f IP4.GATEWAY device show "$INTERFACE" 2>/dev/null | cut -d: -f2 | head -1)
    if [[ -n "$dns" ]]; then
        echo "$dns"
        return
    fi
    # Last resort: hardcoded ProtonVPN default
    echo "10.96.0.1"
}

get_vpn_server_ip() {
    # Detect VPN server IP from host routes via physical interface
    # NM adds a static host route for the VPN endpoint
    ip route show | awk '
        /proto static/ && !/^default/ && !/^10\./ && !/^172\./ && !/^192\.168\./ && !/^169\.254\./ {
            print $1; exit
        }
    '
}

protect() {
    mkdir -p "$STATE_DIR"

    # --- DNS: replace resolv.conf with VPN-only DNS ---
    local vpn_dns
    vpn_dns=$(get_vpn_dns)

    if [[ -L "$RESOLV" ]]; then
        readlink "$RESOLV" > "$STATE_DIR/resolv.conf.target"
    elif [[ -f "$RESOLV" ]] && ! grep -q "$MARKER" "$RESOLV"; then
        # Regular file, not ours — save a copy
        cp "$RESOLV" "$STATE_DIR/resolv.conf.backup"
    fi

    rm -f "$RESOLV"
    cat > "$RESOLV" <<EOF
$MARKER
nameserver $vpn_dns
EOF
    log "DNS locked to $vpn_dns"

    # --- IPv6: disable globally ---
    sysctl -n net.ipv6.conf.all.disable_ipv6 > "$STATE_DIR/ipv6_all.state"
    sysctl -n net.ipv6.conf.default.disable_ipv6 > "$STATE_DIR/ipv6_default.state"
    sysctl -q -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -q -w net.ipv6.conf.default.disable_ipv6=1
    log "IPv6 disabled"

    # --- Kill switch: iptables ---
    local vpn_server
    vpn_server=$(get_vpn_server_ip)

    # Save for cleanup
    echo "$vpn_server" > "$STATE_DIR/vpn_server_ip"

    # Create chain (flush if exists from prior run)
    iptables -N "$CHAIN" 2>/dev/null
    iptables -F "$CHAIN"

    # Allow established/related (don't break ongoing connections)
    iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow loopback
    iptables -A "$CHAIN" -o lo -j ACCEPT

    # Allow VPN tunnel
    iptables -A "$CHAIN" -o tun+ -j ACCEPT

    # Allow traffic to VPN server (maintains tunnel)
    if [[ -n "$vpn_server" ]]; then
        iptables -A "$CHAIN" -d "$vpn_server" -j ACCEPT
    fi

    # Allow LAN
    iptables -A "$CHAIN" -d 192.168.0.0/16 -j ACCEPT

    # Allow Docker/container networks
    iptables -A "$CHAIN" -d 172.16.0.0/12 -j ACCEPT
    iptables -A "$CHAIN" -o br+ -j ACCEPT
    iptables -A "$CHAIN" -o docker+ -j ACCEPT
    iptables -A "$CHAIN" -o veth+ -j ACCEPT
    iptables -A "$CHAIN" -o vir+ -j ACCEPT

    # Allow other private ranges
    iptables -A "$CHAIN" -d 10.0.0.0/8 -j ACCEPT

    # Allow DHCP (needed for lease renewals)
    iptables -A "$CHAIN" -p udp --dport 67:68 -j ACCEPT

    # Allow link-local, multicast, broadcast
    iptables -A "$CHAIN" -d 169.254.0.0/16 -j ACCEPT
    iptables -A "$CHAIN" -d 224.0.0.0/4 -j ACCEPT
    iptables -A "$CHAIN" -d 255.255.255.255/32 -j ACCEPT

    # DROP everything else (kill switch)
    iptables -A "$CHAIN" -j DROP

    # Insert jump into OUTPUT (idempotent — check first)
    iptables -C OUTPUT -j "$CHAIN" 2>/dev/null || iptables -I OUTPUT 1 -j "$CHAIN"

    log "Kill switch active (VPN server: ${vpn_server:-unknown})"

    touch "$STATE_DIR/active"
    log "Protection activated"
}

restore() {
    # --- DNS: restore original resolv.conf ---
    if [[ -f "$STATE_DIR/resolv.conf.target" ]]; then
        local target
        target=$(cat "$STATE_DIR/resolv.conf.target")
        rm -f "$RESOLV"
        ln -sf "$target" "$RESOLV"
        log "DNS restored (symlink → $target)"
    elif [[ -f "$STATE_DIR/resolv.conf.backup" ]]; then
        cp "$STATE_DIR/resolv.conf.backup" "$RESOLV"
        log "DNS restored (from backup)"
    elif grep -q "$MARKER" "$RESOLV" 2>/dev/null; then
        # Stale file with our marker, no state — restore default symlink
        rm -f "$RESOLV"
        ln -sf "$RESOLV_DEFAULT_TARGET" "$RESOLV"
        log "DNS restored (default symlink)"
    fi

    # --- IPv6: restore ---
    if [[ -f "$STATE_DIR/ipv6_all.state" ]]; then
        sysctl -q -w "net.ipv6.conf.all.disable_ipv6=$(cat "$STATE_DIR/ipv6_all.state")"
    else
        sysctl -q -w net.ipv6.conf.all.disable_ipv6=0
    fi
    if [[ -f "$STATE_DIR/ipv6_default.state" ]]; then
        sysctl -q -w "net.ipv6.conf.default.disable_ipv6=$(cat "$STATE_DIR/ipv6_default.state")"
    else
        sysctl -q -w net.ipv6.conf.default.disable_ipv6=0
    fi
    log "IPv6 restored"

    # --- Kill switch: remove iptables chain ---
    iptables -D OUTPUT -j "$CHAIN" 2>/dev/null
    iptables -F "$CHAIN" 2>/dev/null
    iptables -X "$CHAIN" 2>/dev/null
    log "Kill switch removed"

    rm -rf "$STATE_DIR"
    log "Protection deactivated"
}

cleanup_stale() {
    # Called on physical interface up — cleans up after crashes/reboots
    # Only act if no VPN is currently active
    if nmcli -t -f TYPE connection show --active 2>/dev/null | grep -q vpn; then
        return
    fi

    local needs_cleanup=false

    if [[ -f "$STATE_DIR/active" ]]; then
        needs_cleanup=true
    elif grep -q "$MARKER" "$RESOLV" 2>/dev/null; then
        needs_cleanup=true
    fi

    if [[ "$needs_cleanup" == "true" ]]; then
        log "Stale protection detected, cleaning up"
        restore
    fi
}

case "$ACTION" in
    vpn-up)
        protect
        ;;
    vpn-down)
        restore
        ;;
    up)
        cleanup_stale
        ;;
esac

exit 0
