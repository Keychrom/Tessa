#!/usr/bin/env python3
import os
import time

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST = "org.freedesktop.portal.ScreenCast"
REQUESTS = "org.freedesktop.portal.Request"

conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
responses = {}
counter = 0


def on_response(connection, sender, path, interface, signal, params):
    response, results = params.unpack()
    responses[path] = (response, results)
    print(f"response {path} code={response} keys={list(results)}", flush=True)


conn.signal_subscribe(None, REQUESTS, "Response", None, None,
                      Gio.DBusSignalFlags.NONE, on_response)


def variant(value):
    return GLib.Variant("s", value)


def wait_response(path, timeout=20.0):
    deadline = time.time() + timeout
    ctx = GLib.MainContext.default()
    while path not in responses:
        while ctx.iteration(False):
            pass
        if time.time() >= deadline:
            raise RuntimeError(f"timeout waiting for {path}")
        time.sleep(0.05)
    return responses[path]


def call_request(method, args, token):
    print(f"call {method} token={token}", flush=True)
    result = conn.call_sync(PORTAL, PORTAL_PATH, SCREENCAST, method, args, None,
                            Gio.DBusCallFlags.NONE, 10000, None)
    path = result.unpack()[0]
    print(f"request path {path}", flush=True)
    return path


def token():
    global counter
    counter += 1
    return f"tessa_portal_{os.getpid()}_{counter}"


def main():
    create_token = token()
    session_token = token()
    options = {
        "handle_token": variant(create_token),
        "session_handle_token": variant(session_token),
    }
    path = call_request("CreateSession", GLib.Variant("(a{sv})", (options,)),
                        create_token)
    code, results = wait_response(path)
    if code != 0:
        raise RuntimeError(f"CreateSession failed: {code}")
    handle = results.get("session_handle")
    if isinstance(handle, GLib.Variant):
        session = handle.get_string()
    else:
        session = handle
    print(f"session {session}", flush=True)

    select_token = token()
    options = {
        "handle_token": variant(select_token),
        "types": GLib.Variant("u", 1),
        "multiple": GLib.Variant("b", False),
        "cursor_mode": GLib.Variant("u", 1),
    }
    path = call_request("SelectSources",
                        GLib.Variant("(oa{sv})", (session, options)),
                        select_token)
    code, _ = wait_response(path)
    if code != 0:
        raise RuntimeError(f"SelectSources failed: {code}")

    start_token = token()
    options = {"handle_token": variant(start_token)}
    path = call_request("Start",
                        GLib.Variant("(osa{sv})", (session, "", options)),
                        start_token)
    code, results = wait_response(path)
    if code != 0:
        raise RuntimeError(f"Start failed: {code}")
    streams = results.get("streams")
    if isinstance(streams, GLib.Variant):
        streams = streams.unpack()
    print(f"streams {streams}", flush=True)
    if not streams:
        raise RuntimeError("no streams returned")
    node = streams[0][0]
    print(f"node {node}", flush=True)

    result, fd_list = conn.call_with_unix_fd_list_sync(
        PORTAL, PORTAL_PATH, SCREENCAST, "OpenPipeWireRemote",
        GLib.Variant("(oa{sv})", (session, {})),
        None, Gio.DBusCallFlags.NONE, 10000, None, None)
    fd = fd_list.get(0)
    print(f"remote fd {fd} variant={result.print_(True)}", flush=True)
    os.close(fd)
    print("portal screencast ok", flush=True)


main()
