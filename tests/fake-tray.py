#!/usr/bin/env python3
"""Minimal StatusNotifierItem used by tests/tray.sh."""
import os
import sys

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

COMMAND_LOG = sys.argv[1]
READY_FILE = sys.argv[2]
BUS_NAME = "org.kde.StatusNotifierItem.tessatest"
PATH = "/StatusNotifierItem"
SNI = "org.kde.StatusNotifierItem"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"


def make_icon(size=22):
    """ARGB32 pixels in network byte order, as required by IconPixmap."""
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            border = x < 2 or y < 2 or x >= size - 2 or y >= size - 2
            if border or abs(x - y) < 2:
                pixels.extend((255, 245, 158, 66))
            else:
                pixels.extend((255, 48, 110, 190))
    return bytes(pixels)


def icon_pixmaps():
    builder = GLib.VariantBuilder.new(GLib.VariantType.new("a(iiay)"))
    item = GLib.VariantBuilder.new(GLib.VariantType.new("(iiay)"))
    item.add_value(GLib.Variant("i", 22))
    item.add_value(GLib.Variant("i", 22))
    item.add_value(GLib.Variant("ay", make_icon()))
    builder.add_value(item.end())
    return builder.end()


ICON_PIXMAP = icon_pixmaps()
state = {"title": "Test Tray"}


def append_command(name):
    with open(COMMAND_LOG, "a", encoding="utf-8") as handle:
        handle.write(name + "\n")


def on_properties(connection, sender, path, interface, method, params, invocation):
    if method == "GetAll":
        requested = params.unpack()[0]
        if requested == SNI:
            values = {
                "Id": GLib.Variant("s", "tessatest"),
                "Title": GLib.Variant("s", state["title"]),
                "Status": GLib.Variant("s", "Active"),
                "IconName": GLib.Variant("s", "tessa-test"),
                "IconPixmap": ICON_PIXMAP,
            }
            invocation.return_value(GLib.Variant("(a{sv})", (values,)))
            return
    invocation.return_value(GLib.Variant("()"))


def on_item(connection, sender, path, interface, method, params, invocation):
    append_command(method)
    invocation.return_value(None)


def register_objects(connection):
    xml = f"""
    <node>
      <interface name="org.freedesktop.DBus.Properties">
        <method name="GetAll">
          <arg type="s" direction="in"/>
          <arg type="a{{sv}}" direction="out"/>
        </method>
      </interface>
      <interface name="{SNI}">
        <method name="Activate">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
        </method>
        <method name="SecondaryActivate">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
        </method>
        <method name="ContextMenu">
          <arg type="i" direction="in"/>
          <arg type="i" direction="in"/>
        </method>
        <method name="Scroll">
          <arg type="i" direction="in"/>
          <arg type="s" direction="in"/>
        </method>
      </interface>
    </node>
    """
    node = Gio.DBusNodeInfo.new_for_xml(xml)
    connection.register_object(PATH, node.interfaces[0], on_properties, None, None)
    connection.register_object(PATH, node.interfaces[1], on_item, None, None)


conn = None
ready_written = False


def register_with_watcher():
    global ready_written
    try:
        conn.call_sync(
            WATCHER,
            WATCHER_PATH,
            WATCHER,
            "RegisterStatusNotifierItem",
            GLib.Variant("(s)", (BUS_NAME,)),
            None,
            Gio.DBusCallFlags.NONE,
            1000,
            None,
        )
    except GLib.Error as error:
        print(f"watcher not ready: {error.message}", file=sys.stderr)
        return True
    if not ready_written:
        with open(READY_FILE, "w", encoding="utf-8") as handle:
            handle.write("ready\n")
        ready_written = True
    return False


def on_bus(connection, name):
    global conn
    conn = connection
    register_objects(connection)


def on_name_acquired(connection, name):
    GLib.timeout_add(100, register_with_watcher)


def on_name_lost(connection, name):
    print("could not own", name, file=sys.stderr)
    sys.exit(1)


Gio.bus_own_name(
    Gio.BusType.SESSION,
    BUS_NAME,
    Gio.BusNameOwnerFlags.NONE,
    on_bus,
    on_name_acquired,
    on_name_lost,
)
GLib.MainLoop().run()
