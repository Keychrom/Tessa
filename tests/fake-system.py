#!/usr/bin/env python3
"""Minimal fake logind + power-profiles-daemon for Tessa tests."""
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

LOG = os.environ.get("FAKE_SYSTEM_LOG", "/tmp/fake-system.log")
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
for name in ("org.freedesktop.login1", "org.freedesktop.UPower.PowerProfiles"):
    reply = conn.call_sync(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "RequestName",
        GLib.Variant("(su)", (name, 0)),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    if reply.unpack()[0] not in (1, 4):
        print(f"cannot own {name}", file=sys.stderr)
        sys.exit(1)

LOGIN = "/org/freedesktop/login1"
SESSION = LOGIN + "/session/test"
PPD = "/org/freedesktop/UPower/PowerProfiles"
profiles = [
    {"Profile": GLib.Variant("s", "power-saver")},
    {"Profile": GLib.Variant("s", "balanced")},
    {"Profile": GLib.Variant("s", "performance")},
]
ppd_props = {
    "ActiveProfile": GLib.Variant("s", "balanced"),
    "Profiles": GLib.Variant("aa{sv}", profiles),
}


def log(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")


def finish(inv, value=None):
    inv.return_value(value)


def on_method(connection, sender, path, interface, method, params, inv):
    if interface == "org.freedesktop.login1.Manager" and method == "GetSessionByPID":
        finish(inv, GLib.Variant("(o)", (SESSION,)))
        return
    if interface == "org.freedesktop.login1.Session" and method == "SetBrightness":
        subsystem, name, value = params.unpack()
        log(f"SetBrightness {subsystem} {name} {value}")
        finish(inv)
        return
    if interface == "org.freedesktop.DBus.Properties":
        if method == "GetAll":
            finish(inv, GLib.Variant("(a{sv})", (dict(ppd_props),)))
            return
        if method == "Get":
            key = params.unpack()[1]
            finish(inv, GLib.Variant("(v)", (ppd_props[key],)))
            return
        if method == "Set":
            _iface, key, value = params.unpack()
            ppd_props[key] = value
            log(f"Set {key} {value}")
            finish(inv)
            return
    inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


NODE = """<node>
  <interface name='org.freedesktop.login1.Manager'>
    <method name='GetSessionByPID'><arg type='u' direction='in'/><arg type='o' direction='out'/></method>
  </interface>
  <interface name='org.freedesktop.login1.Session'>
    <method name='SetBrightness'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='u' direction='in'/></method>
  </interface>
  <interface name='org.freedesktop.DBus.Properties'>
    <method name='GetAll'><arg type='s' direction='in'/><arg type='a{sv}' direction='out'/></method>
    <method name='Get'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='out'/></method>
    <method name='Set'><arg type='s' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/></method>
  </interface>
</node>"""
info = Gio.DBusNodeInfo.new_for_xml(NODE)
for path in (LOGIN, SESSION, PPD):
    for iface in info.interfaces:
        try:
            conn.register_object(path, iface, on_method, None, None)
        except Exception:
            pass

GLib.MainLoop().run()
