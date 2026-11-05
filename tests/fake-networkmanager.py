#!/usr/bin/env python3
"""Minimal fake NetworkManager for Tessa control-center tests.

The test process sets DBUS_SYSTEM_BUS_ADDRESS to a private bus. The fake
implements only the properties and methods tessa-panel reads/writes.
"""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

LOG = os.environ.get("FAKE_NM_LOG", "/tmp/fake-nm.log")
ADDRESS = os.environ.get("DBUS_SYSTEM_BUS_ADDRESS")
if not ADDRESS:
    print("DBUS_SYSTEM_BUS_ADDRESS is required", file=sys.stderr)
    sys.exit(1)

conn = Gio.DBusConnection.new_for_address_sync(
    ADDRESS,
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
    | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
    None,
    None,
)
reply = conn.call_sync(
    "org.freedesktop.DBus",
    "/org/freedesktop/DBus",
    "org.freedesktop.DBus",
    "RequestName",
    GLib.Variant("(su)", ("org.freedesktop.NetworkManager", 0)),
    None,
    Gio.DBusCallFlags.NONE,
    -1,
    None,
)
if reply.unpack()[0] not in (1, 4):
    print("cannot own NetworkManager name", file=sys.stderr)
    sys.exit(1)

ROOT = "/org/freedesktop/NetworkManager"
DEV = ROOT + "/Devices/0"
WIRELESS = DEV
AP1 = ROOT + "/AccessPoint/1"
AP2 = ROOT + "/AccessPoint/2"
SETTINGS = ROOT + "/Settings"

props = {
    ROOT: {
        "org.freedesktop.NetworkManager": {
            "WirelessEnabled": GLib.Variant("b", True),
            "WirelessHardwareEnabled": GLib.Variant("b", True),
            "Devices": GLib.Variant("ao", [DEV]),
            "ActiveConnections": GLib.Variant("ao", []),
            "Connectivity": GLib.Variant("u", 1),
        },
    },
    DEV: {
        "org.freedesktop.NetworkManager.Device": {
            "DeviceType": GLib.Variant("u", 2),
            "State": GLib.Variant("u", 100),
            "ActiveConnection": GLib.Variant("o", "/"),
            "Interface": GLib.Variant("s", "wlan0"),
        },
        "org.freedesktop.NetworkManager.Device.Wireless": {
            "AccessPoints": GLib.Variant("ao", [AP1, AP2]),
            "ActiveAccessPoint": GLib.Variant("o", AP2),
            "HwAddress": GLib.Variant("s", "00:11:22:33:44:55"),
        },
    },
    AP1: {
        "org.freedesktop.NetworkManager.AccessPoint": {
            "Ssid": GLib.Variant("ay", list(b"TestNet")),
            "Strength": GLib.Variant("y", 82),
            "Flags": GLib.Variant("u", 1),
            "WpaFlags": GLib.Variant("u", 0x100),
            "RsnFlags": GLib.Variant("u", 0x100),
            "HwAddress": GLib.Variant("s", "00:11:22:33:44:55"),
        },
    },
    AP2: {
        "org.freedesktop.NetworkManager.AccessPoint": {
            "Ssid": GLib.Variant("ay", list(b"OpenNet")),
            "Strength": GLib.Variant("y", 64),
            "Flags": GLib.Variant("u", 0),
            "WpaFlags": GLib.Variant("u", 0),
            "RsnFlags": GLib.Variant("u", 0),
            "HwAddress": GLib.Variant("s", "00:11:22:33:44:66"),
        },
    },
    SETTINGS: {
        "org.freedesktop.NetworkManager.Settings": {},
    },
}

NODE = """<node>
  <interface name='org.freedesktop.DBus.Properties'>
    <method name='Get'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='out'/></method>
    <method name='GetAll'><arg type='s' direction='in'/><arg type='a{sv}' direction='out'/></method>
    <method name='Set'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/></method>
  </interface>
  <interface name='org.freedesktop.NetworkManager'>
    <method name='ActivateConnection'><arg type='o' direction='in'/><arg type='o' direction='in'/><arg type='o' direction='in'/><arg type='o' direction='out'/></method>
    <method name='AddAndActivateConnection'><arg type='a{sa{sv}}' direction='in'/><arg type='o' direction='in'/><arg type='o' direction='in'/><arg type='o' direction='out'/><arg type='o' direction='out'/></method>
    <method name='DeactivateConnection'><arg type='o' direction='in'/></method>
  </interface>
  <interface name='org.freedesktop.NetworkManager.Device'>
  </interface>
  <interface name='org.freedesktop.NetworkManager.Device.Wireless'>
    <method name='RequestScan'><arg type='a{sv}' direction='in'/></method>
  </interface>
  <interface name='org.freedesktop.NetworkManager.Settings'>
    <method name='ListConnections'><arg type='ao' direction='out'/></method>
  </interface>
  <interface name='org.freedesktop.NetworkManager.AccessPoint'>
  </interface>
  <interface name='org.freedesktop.NetworkManager.Settings.Connection'>
    <method name='Delete'/>
  </interface>
</node>"""
node_info = Gio.DBusNodeInfo.new_for_xml(NODE)


def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


def finish(inv, value=None):
    if value is None:
        inv.return_value(None)
    else:
        inv.return_value(value)


def on_method(connection, sender, path, interface, method, params, inv):
    if interface == "org.freedesktop.DBus.Properties":
        if method == "GetAll":
            iface = params.unpack()[0]
            values = props.get(path, {}).get(iface, {})
            finish(inv, GLib.Variant("(a{sv})", (values,)))
            return
        if method == "Get":
            iface, key = params.unpack()
            values = props.get(path, {}).get(iface, {})
            if key not in values:
                inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownProperty", key)
                return
            finish(inv, GLib.Variant("(v)", (values[key],)))
            return
        if method == "Set":
            iface, key, value = params.unpack()
            props.setdefault(path, {}).setdefault(iface, {})[key] = value
            log(f"Set {iface} {key} {value}")
            finish(inv)
            return
    if interface == "org.freedesktop.NetworkManager.Device.Wireless" and method == "RequestScan":
        log("RequestScan")
        finish(inv)
        return
    if interface == "org.freedesktop.NetworkManager" and method == "ActivateConnection":
        log("ActivateConnection " + " ".join(str(x) for x in params.unpack()))
        finish(inv, GLib.Variant("(o)", ("/org/freedesktop/NetworkManager/ActiveConnection/1",)))
        return
    if interface == "org.freedesktop.NetworkManager" and method == "AddAndActivateConnection":
        settings, device, specific = params.unpack()
        ssid = ""
        psk = ""
        try:
            wireless = settings.get("802-11-wireless", {})
            ssid = bytes(wireless.get("ssid", b"")).decode("utf-8", "replace")
            sec = settings.get("802-11-wireless-security", {})
            psk = sec.get("psk", "")
        except Exception:
            pass
        log(f"AddAndActivateConnection ssid={ssid} psk={psk} specific={specific}")
        finish(inv, GLib.Variant("(oo)", (
            "/org/freedesktop/NetworkManager/Settings/test",
            "/org/freedesktop/NetworkManager/ActiveConnection/2",
        )))
        return
    if interface == "org.freedesktop.NetworkManager" and method == "DeactivateConnection":
        log("DeactivateConnection")
        finish(inv)
        return
    if interface == "org.freedesktop.NetworkManager.Settings" and method == "ListConnections":
        finish(inv, GLib.Variant("(ao)", ([],)))
        return
    inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


registrations = []
for path in props:
    for iface in node_info.interfaces:
        try:
            reg = conn.register_object(path, iface, on_method, None, None)
            registrations.append(reg)
        except Exception:
            pass
# APs share the AccessPoint interface; register on each path.
ap_info = next(i for i in node_info.interfaces if i.name == "org.freedesktop.NetworkManager.AccessPoint") if any(
    i.name == "org.freedesktop.NetworkManager.AccessPoint" for i in node_info.interfaces) else None

GLib.MainLoop().run()
