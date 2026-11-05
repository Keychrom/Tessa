#!/usr/bin/env python3
"""Minimal fake BlueZ service for Tessa control-center tests."""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

LOG = os.environ.get("FAKE_BT_LOG", "/tmp/fake-bt.log")
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
    GLib.Variant("(su)", ("org.bluez", 0)),
    None,
    Gio.DBusCallFlags.NONE,
    -1,
    None,
)
if reply.unpack()[0] not in (1, 4):
    print("cannot own org.bluez", file=sys.stderr)
    sys.exit(1)

ADAPTER = "/org/bluez/hci0"
DEVICE = ADAPTER + "/dev_AA"
agent_sender = None
agent_path = None
paired = False
connected = False


def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


def managed_objects():
    adapter = {
        "Powered": GLib.Variant("b", True),
        "Discovering": GLib.Variant("b", False),
        "Alias": GLib.Variant("s", "Test Adapter"),
        "Address": GLib.Variant("s", "AA:BB:CC:DD:EE:FF"),
    }
    device = {
        "Name": GLib.Variant("s", "Test Headset"),
        "Alias": GLib.Variant("s", "Test Headset"),
        "Paired": GLib.Variant("b", paired),
        "Connected": GLib.Variant("b", connected),
        "Trusted": GLib.Variant("b", False),
        "RSSI": GLib.Variant("n", -48),
        "Icon": GLib.Variant("s", "audio-headset"),
        "Adapter": GLib.Variant("o", ADAPTER),
    }
    battery = {"Percentage": GLib.Variant("y", 80)}
    return {
        ADAPTER: {"org.bluez.Adapter1": adapter},
        DEVICE: {
            "org.bluez.Device1": device,
            "org.bluez.Battery1": battery,
        },
    }


def finish(inv, value=None):
    inv.return_value(value)


def on_agent_reply(connection, result, inv):
    try:
        connection.call_finish(result)
        log("agent confirmed")
        global paired
        paired = True
        finish(inv)
    except Exception as exc:  # noqa: BLE001
        log(f"agent rejected: {exc}")
        inv.return_dbus_error("org.bluez.Error.Rejected", "Rejected")


def on_method(connection, sender, path, interface, method, params, inv):
    global agent_sender, agent_path, connected
    if interface == "org.freedesktop.DBus.ObjectManager" and method == "GetManagedObjects":
        objects = managed_objects()
        finish(inv, GLib.Variant("(a{oa{sa{sv}}})", (objects,)))
        return
    if interface == "org.bluez.AgentManager1":
        if method == "RegisterAgent":
            agent_path, _cap = params.unpack()
            agent_sender = sender
            log(f"RegisterAgent {agent_path} sender={sender}")
            finish(inv)
            return
        if method == "RequestDefaultAgent":
            log("RequestDefaultAgent")
            finish(inv)
            return
    if interface == "org.bluez.Adapter1":
        if method in ("StartDiscovery", "StopDiscovery"):
            log(method)
            finish(inv)
            return
        if method == "RemoveDevice":
            log("RemoveDevice")
            finish(inv)
            return
    if interface == "org.bluez.Device1":
        if method == "Pair":
            log("Pair")
            if not agent_sender or not agent_path:
                inv.return_dbus_error("org.bluez.Error.Failed", "No agent")
                return
            connection.call(
                agent_sender,
                agent_path,
                "org.bluez.Agent1",
                "RequestConfirmation",
                GLib.Variant("(ou)", (DEVICE, 123456)),
                None,
                Gio.DBusCallFlags.NONE,
                30000,
                None,
                on_agent_reply,
                inv,
            )
            return
        if method == "Connect":
            log("Connect")
            connected = True
            finish(inv)
            return
        if method == "Disconnect":
            log("Disconnect")
            connected = False
            finish(inv)
            return
    if interface == "org.freedesktop.DBus.Properties":
        if method == "GetAll":
            iface = params.unpack()[0]
            values = managed_objects().get(path, {}).get(iface, {})
            finish(inv, GLib.Variant("(a{sv})", (values,)))
            return
        if method == "Set":
            _iface, key, value = params.unpack()
            log(f"Set {key} {value}")
            finish(inv)
            return
    inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


NODE = """<node>
  <interface name='org.freedesktop.DBus.ObjectManager'>
    <method name='GetManagedObjects'><arg type='a{oa{sa{sv}}}' direction='out'/></method>
  </interface>
  <interface name='org.bluez.AgentManager1'>
    <method name='RegisterAgent'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
    <method name='RequestDefaultAgent'><arg type='o' direction='in'/></method>
  </interface>
  <interface name='org.bluez.Adapter1'>
    <method name='StartDiscovery'/>
    <method name='StopDiscovery'/>
    <method name='RemoveDevice'><arg type='o' direction='in'/></method>
  </interface>
  <interface name='org.bluez.Device1'>
    <method name='Pair'/>
    <method name='Connect'/>
    <method name='Disconnect'/>
  </interface>
  <interface name='org.freedesktop.DBus.Properties'>
    <method name='GetAll'><arg type='s' direction='in'/><arg type='a{sv}' direction='out'/></method>
    <method name='Set'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/></method>
  </interface>
</node>"""
info = Gio.DBusNodeInfo.new_for_xml(NODE)
for path in ("/", "/org/bluez", ADAPTER, DEVICE):
    for iface in info.interfaces:
        try:
            conn.register_object(path, iface, on_method, None, None)
        except Exception:
            pass

GLib.MainLoop().run()
