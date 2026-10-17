#!/usr/bin/env python3
"""
VPN System Tray Applet
Uses NetworkManager to manage VPN connections (ProtonVPN + NordVPN).
Dynamically discovers all VPN connections in NM.
Shows status via Ayatana AppIndicator in the system tray.
"""

import subprocess
import signal
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, GLib, AyatanaAppIndicator3

POLL_INTERVAL = 3000  # ms
VPN_PROVIDERS = ["protonvpn", "nordvpn"]


def is_managed_vpn(name):
    """Check if a VPN connection belongs to a managed provider."""
    lower = name.lower()
    return any(p in lower for p in VPN_PROVIDERS)


class ProtonVPNTray:
    def __init__(self):
        self.connected = False
        self.active_conn = ""

        self.indicator = AyatanaAppIndicator3.Indicator.new(
            "protonvpn-tray",
            "protonvpngui-disconnected",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("ProtonVPN")

        self.build_menu()
        self.update_status()
        GLib.timeout_add(POLL_INTERVAL, self.update_status)

    def get_all_vpn_connections(self):
        """Get all ProtonVPN connections from NetworkManager."""
        connections = []
        try:
            result = subprocess.run(
                ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"],
                capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.strip().split("\n"):
                parts = line.split(":")
                if len(parts) >= 2 and parts[1] == "vpn" and is_managed_vpn(parts[0]):
                    connections.append(parts[0])
        except Exception:
            pass
        return sorted(connections)

    def get_vpn_status(self):
        """Check if any ProtonVPN connection is active."""
        try:
            result = subprocess.run(
                ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"],
                capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.strip().split("\n"):
                parts = line.split(":")
                if len(parts) >= 2 and is_managed_vpn(parts[0]) and parts[1] == "vpn":
                    return True, parts[0]
        except Exception:
            pass
        return False, ""

    def build_menu(self):
        menu = Gtk.Menu()

        self.status_item = Gtk.MenuItem(label="Status: Checking...")
        self.status_item.set_sensitive(False)
        menu.append(self.status_item)

        self.server_item = Gtk.MenuItem(label="")
        self.server_item.set_sensitive(False)
        menu.append(self.server_item)

        menu.append(Gtk.SeparatorMenuItem())

        # Servers submenu
        servers_item = Gtk.MenuItem(label="Connect")
        self.servers_menu = Gtk.Menu()
        servers_item.set_submenu(self.servers_menu)
        menu.append(servers_item)
        self.populate_servers()

        self.disconnect_item = Gtk.MenuItem(label="Disconnect")
        self.disconnect_item.connect("activate", self.on_disconnect)
        menu.append(self.disconnect_item)

        menu.append(Gtk.SeparatorMenuItem())

        refresh_item = Gtk.MenuItem(label="Refresh Servers")
        refresh_item.connect("activate", self.on_refresh)
        menu.append(refresh_item)

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self.on_quit)
        menu.append(quit_item)

        menu.show_all()
        self.indicator.set_menu(menu)

    def populate_servers(self):
        """Populate the servers submenu with all available ProtonVPN connections."""
        for child in self.servers_menu.get_children():
            self.servers_menu.remove(child)

        connections = self.get_all_vpn_connections()
        if not connections:
            empty = Gtk.MenuItem(label="No servers found")
            empty.set_sensitive(False)
            self.servers_menu.append(empty)
        else:
            for conn in connections:
                # Extract a readable label: "us-free-33.protonvpn.udp" → "US Free 33"
                label = self.format_server_name(conn)
                item = Gtk.MenuItem(label=label)
                item.connect("activate", self.on_connect, conn)
                self.servers_menu.append(item)

        self.servers_menu.show_all()

    def format_server_name(self, conn_name):
        """Turn NM connection name into readable label."""
        # "us-free-33.protonvpn.udp" → "US Free #33 (UDP)"
        # "us12072.nordvpn.com.udp" → "Nord US #12072 (UDP)"
        name = conn_name.lower()
        proto = ""
        if name.endswith(".udp"):
            proto = "UDP"
            name = name[:-4]
        elif name.endswith(".tcp"):
            proto = "TCP"
            name = name[:-4]

        is_nord = "nordvpn" in name
        name = name.replace(".protonvpn", "").replace(".nordvpn.com", "").replace(".nordvpn", "")

        if is_nord:
            # "us12072" → "Nord US #12072"
            import re
            m = re.match(r"([a-z]+)(\d+)", name)
            if m:
                result = f"Nord {m.group(1).upper()} #{m.group(2)}"
            else:
                result = f"Nord {name.upper()}"
        else:
            # ProtonVPN: split on - and capitalize
            parts = name.split("-")
            formatted = []
            for part in parts:
                if part.isdigit():
                    formatted.append(f"#{part}")
                else:
                    formatted.append(part.upper())
            result = " ".join(formatted)

        if proto:
            result += f" ({proto})"
        return result

    def update_status(self):
        connected, server = self.get_vpn_status()
        self.connected = connected
        self.active_conn = server

        if connected:
            self.indicator.set_icon_full("protonvpngui-connected", "Connected")
            self.status_item.set_label("Status: Connected")
            self.server_item.set_label(f"Server: {self.format_server_name(server)}")
            self.server_item.show()
            self.disconnect_item.set_sensitive(True)
        else:
            self.indicator.set_icon_full("protonvpngui-disconnected", "Disconnected")
            self.status_item.set_label("Status: Disconnected")
            self.server_item.set_label("")
            self.server_item.hide()
            self.disconnect_item.set_sensitive(False)

        return True  # keep polling

    def on_connect(self, _, conn_name):
        # Disconnect current if any, then connect new
        if self.connected and self.active_conn:
            subprocess.Popen(["nmcli", "connection", "down", self.active_conn])

        self.status_item.set_label("Status: Connecting...")
        self.indicator.set_icon_full("protonvpngui-no-network", "Connecting")
        subprocess.Popen(["nmcli", "connection", "up", conn_name])
        GLib.timeout_add(2000, self.update_status)

    def on_disconnect(self, _):
        if self.active_conn:
            self.status_item.set_label("Status: Disconnecting...")
            subprocess.Popen(["nmcli", "connection", "down", self.active_conn])
            GLib.timeout_add(2000, self.update_status)

    def on_refresh(self, _):
        self.populate_servers()

    def on_quit(self, _):
        Gtk.main_quit()


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    ProtonVPNTray()
    Gtk.main()


if __name__ == "__main__":
    main()
