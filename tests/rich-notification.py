#!/usr/bin/env python3
"""Send one rich notification and print its id. Used by tests/notifications.sh."""
import sys

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


def icon_image(size=32):
    """ARGB32 pixels in network byte order, as required by image-data."""
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            inside = 4 <= x < size - 4 and 4 <= y < size - 4
            if inside:
                pixels.extend((255, 48, 110, 190))
            else:
                pixels.extend((255, 245, 158, 66))
    image = GLib.VariantBuilder.new(GLib.VariantType.new("(iiibiiay)"))
    image.add_value(GLib.Variant("i", size))
    image.add_value(GLib.Variant("i", size))
    image.add_value(GLib.Variant("i", size * 4))
    image.add_value(GLib.Variant("b", True))
    image.add_value(GLib.Variant("i", 8))
    image.add_value(GLib.Variant("i", 4))
    image.add_value(GLib.Variant("ay", bytes(pixels)))
    return image.end()


def main():
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    actions = GLib.Variant("as", [
        "default", "Open",
        "reply", "Reply",
        "dismiss", "Dismiss",
    ])
    hints = {
        "image-data": icon_image(),
        "icon-name": GLib.Variant("s", "tessa-test"),
    }
    result = connection.call_sync(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify",
        GLib.Variant("(susssasa{sv}i)", (
            "rich-app",
            0,
            "",
            "Build finished",
            "<b>Bold</b> <i>italic</i> &amp; <u>underline</u>",
            actions,
            hints,
            0,
        )),
        None,
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
    print(result.unpack()[0], flush=True)


main()
