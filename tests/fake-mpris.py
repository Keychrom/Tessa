#!/usr/bin/env python3
"""Minimal MPRIS player used by tests/notifications-media.sh."""
import os
import sys

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

COMMAND_LOG = sys.argv[1]
READY_FILE = sys.argv[2]
BUS_NAME = "org.mpris.MediaPlayer2.tessatest"
PATH = "/org/mpris/MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"

state = {"status": "Playing", "title": "Test Song"}
conn = None


def metadata_variant():
    metadata = {
        "xesam:title": GLib.Variant("s", state["title"]),
        "xesam:artist": GLib.Variant("as", ["Test Artist"]),
    }
    return GLib.Variant("a{sv}", metadata)


def on_properties(connection, sender, path, interface, method, params, invocation):
    if method == "GetAll":
        requested = params.unpack()[0]
        if requested == PLAYER:
            values = {
                "PlaybackStatus": GLib.Variant("s", state["status"]),
                "Metadata": metadata_variant(),
            }
            invocation.return_value(GLib.Variant("(a{sv})", (values,)))
            return
    invocation.return_value(GLib.Variant("()"))


def append_command(name):
    with open(COMMAND_LOG, "a", encoding="utf-8") as handle:
        handle.write(name + "\n")


def on_player(connection, sender, path, interface, method, params, invocation):
    append_command(method)
    if method == "PlayPause":
        state["status"] = "Paused" if state["status"] == "Playing" else "Playing"
    elif method == "Next":
        state["title"] = "Track 2"
    elif method == "Previous":
        state["title"] = "Test Song"
    invocation.return_value(None)


def register(connection):
    xml = """
    <node>
      <interface name="org.freedesktop.DBus.Properties">
        <method name="GetAll">
          <arg type="s" direction="in"/>
          <arg type="a{sv}" direction="out"/>
        </method>
      </interface>
      <interface name="org.mpris.MediaPlayer2.Player">
        <method name="PlayPause"/>
        <method name="Next"/>
        <method name="Previous"/>
      </interface>
    </node>
    """
    node = Gio.DBusNodeInfo.new_for_xml(xml)
    connection.register_object(PATH, node.interfaces[0], on_properties, None, None)
    connection.register_object(PATH, node.interfaces[1], on_player, None, None)


def on_bus(connection, name):
    global conn
    conn = connection
    register(connection)


def on_name_acquired(connection, name):
    with open(READY_FILE, "w", encoding="utf-8") as handle:
        handle.write("ready\n")


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
