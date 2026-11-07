#!/usr/bin/env python3
"""Run tessa-panel under Hyprland or Niri.

The Tessa panel normally talks to the Tessa compositor over a Unix socket using
a small line protocol (WIN/OUT/FOCUSED and CMD ...).  This bridge speaks that
same protocol to the panel and translates it to Hyprland or Niri's IPC.  The
panel itself is unchanged.

Quick start (from a Hyprland or Niri session):

    python3 tools/tessa-panel-compat.py

The bridge creates $XDG_RUNTIME_DIR/tessa.sock, starts one tessa-panel per
output, and prints diagnostics to stderr.  Use --no-spawn to serve state
without starting panels, and --print-state to inspect the translated state.

Open the launcher from a compositor key binding with:

    tessa-panel-compat --send launcher
    tessa-panel-compat --send switcher
    tessa-panel-compat --send control

This is intentionally a small, stdlib-only compatibility layer, not a second
compositor.  It currently supports the state the panel needs for the bar,
workspaces, window list, launcher, and window switcher.  Live per-window
capture depends on the host compositor implementing the relevant ext
protocols; otherwise the panel falls back to screencopy or monograms.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Optional

LOG = logging.getLogger("tessa-panel-compat")

WS_LIMIT = 9
MAX_SOCKET_PATH = 100


class CompatError(RuntimeError):
    """A compositor query or command failed."""


def escape(value: Any) -> str:
    """Escape a field for the Tessa panel line protocol."""
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def as_pair(value: Any, default: tuple[int, int] = (0, 0)) -> tuple[int, int]:
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return as_int(value[0]), as_int(value[1])
    return default


@dataclass
class OutputInfo:
    name: str
    make: str = ""
    model: str = ""
    serial: str = ""
    x: int = 0
    y: int = 0
    width: int = 0
    height: int = 0
    ws: int = 1
    focused: bool = False
    layout: str = ""


@dataclass
class WindowInfo:
    id: int
    ws: int
    focused: bool
    floating: bool
    fullscreen: bool
    app_id: str
    title: str
    output: str
    x: int
    y: int
    width: int
    height: int
    focus_seq: int
    identifier: str = ""
    visible: bool = False
    on_screen: bool = False


@dataclass
class Snapshot:
    outputs: list[OutputInfo] = field(default_factory=list)
    windows: list[WindowInfo] = field(default_factory=list)
    active_ws: int = 1
    focused_id: int = 0
    mode: str = "default"

    def serialize(self) -> bytes:
        lines = ["STATE", f"ACTIVE {max(1, self.active_ws)}", f"MODE {escape(self.mode)}"]
        for out in self.outputs:
            lines.append(
                "OUT {name} {ws} {focused} {layout}".format(
                    name=escape(out.name),
                    ws=max(1, out.ws),
                    focused=1 if out.focused else 0,
                    layout=escape(out.layout),
                ).rstrip()
            )

        counts: dict[int, int] = {}
        for win in self.windows:
            if 1 <= win.ws <= WS_LIMIT:
                counts[win.ws] = counts.get(win.ws, 0) + 1
        for ws in range(1, WS_LIMIT + 1):
            lines.append(f"OCC {ws} {counts.get(ws, 0)}")

        lines.append(f"FOCUSED {self.focused_id}")
        for win in self.windows:
            fields = [
                "WIN",
                str(win.id),
                str(max(1, win.ws)),
                "1" if win.focused else "0",
                "1" if win.floating else "0",
                "1" if win.fullscreen else "0",
                escape(win.app_id),
                escape(win.title),
                escape(win.output),
                str(win.x),
                str(win.y),
                str(win.width),
                str(win.height),
                "0",  # scratchpad
                "1" if win.visible else "0",
                "0",  # group_id
                "0",  # group_active
                "1" if win.on_screen else "0",
                "-1",  # scroll column
                "-1",  # tile
                str(max(0, win.focus_seq)),
                escape(win.identifier),
            ]
            lines.append("\t".join(fields))
        lines.append("END")
        return ("\n".join(lines) + "\n").encode("utf-8")


class Adapter:
    """Common interface for compositor-specific state and commands."""

    name = "base"

    def query(self) -> Snapshot:
        raise NotImplementedError

    def spawn(self, command: str) -> None:
        raise NotImplementedError

    def workspace(self, index: int, output: Optional[str]) -> None:
        raise NotImplementedError

    def focus(self, window_id: int) -> None:
        raise NotImplementedError

    def close(self, window_id: int) -> None:
        raise NotImplementedError


def run_command(args: list[str], timeout: float = 3.0) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise CompatError(f"command not found: {args[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise CompatError(f"command timed out: {' '.join(args)}") from exc


def json_command(args: list[str]) -> Any:
    result = run_command(args)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise CompatError(f"{' '.join(args)} failed: {detail}")
    try:
        return json.loads(result.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise CompatError(f"{' '.join(args)} returned invalid JSON: {exc}") from exc


class HyprlandAdapter(Adapter):
    name = "hyprland"

    def __init__(self, binary: str = "hyprctl") -> None:
        self.binary = binary
        self.windows: dict[int, WindowInfo] = {}
        self.addresses: dict[int, str] = {}

    def _json(self, *args: str) -> Any:
        return json_command([self.binary, "-j", *args])

    def query(self) -> Snapshot:
        monitors = self._json("monitors")
        clients = self._json("clients")
        active = self._json("activewindow")
        if isinstance(monitors, dict):
            monitors = list(monitors.values())
        if not isinstance(monitors, list):
            monitors = []
        if not isinstance(clients, list):
            clients = []
        if not isinstance(active, dict):
            active = {}

        outputs: list[OutputInfo] = []
        by_monitor: dict[int, OutputInfo] = {}
        for monitor in monitors:
            if not isinstance(monitor, dict):
                continue
            name = str(monitor.get("name", ""))
            if not name:
                continue
            ws_obj = monitor.get("activeWorkspace") or {}
            ws = as_int(ws_obj.get("id"), 1)
            output = OutputInfo(
                name=name,
                make=str(monitor.get("make", "") or ""),
                model=str(monitor.get("model", "") or ""),
                serial=str(monitor.get("serial", "") or ""),
                x=as_int(monitor.get("x")),
                y=as_int(monitor.get("y")),
                width=as_int(monitor.get("width")),
                height=as_int(monitor.get("height")),
                ws=max(1, ws),
                focused=bool(monitor.get("focused", False)),
                layout="hyprland",
            )
            outputs.append(output)
            by_monitor[as_int(monitor.get("id"), -1)] = output

        if outputs and not any(out.focused for out in outputs):
            outputs[0].focused = True
        focused_output = next((out for out in outputs if out.focused), outputs[0] if outputs else None)
        active_ws = focused_output.ws if focused_output else 1
        active_address = str(active.get("address", "") or "")
        active_id = 0
        if active_address:
            try:
                active_id = int(active_address, 0)
            except ValueError:
                active_id = 0

        windows: list[WindowInfo] = []
        self.windows.clear()
        self.addresses.clear()
        for order, client in enumerate(clients):
            if not isinstance(client, dict):
                continue
            address = str(client.get("address", "") or "")
            try:
                window_id = int(address, 0)
            except ValueError:
                continue
            workspace = client.get("workspace") or {}
            ws = as_int(workspace.get("id"), 0)
            if ws <= 0:
                # Hyprland uses negative IDs for special workspaces. Tessa's
                # 1-9 bar cannot represent them yet; keep them out of this pass.
                continue
            mapped = bool(client.get("mapped", True))
            hidden = bool(client.get("hidden", False))
            if not mapped or hidden:
                continue
            output = by_monitor.get(as_int(client.get("monitor"), -1))
            if output is None:
                output = next((out for out in outputs if out.ws == ws), None)
            output_name = output.name if output else ""
            visible = bool(output and ws == output.ws)
            focused = bool(active_id and window_id == active_id)
            if not active_id and as_int(client.get("focusHistoryID"), 999) == 0:
                focused = True
            focus_history = as_int(client.get("focusHistoryID"), 1_000_000 + order)
            x, y = as_pair(client.get("at"))
            width, height = as_pair(client.get("size"))
            window = WindowInfo(
                id=window_id,
                ws=ws,
                focused=focused,
                floating=bool(client.get("floating", False)),
                fullscreen=as_int(client.get("fullscreen"), 0) != 0,
                app_id=str(client.get("class", "") or ""),
                title=str(client.get("title", "") or ""),
                output=output_name,
                x=x,
                y=y,
                width=width,
                height=height,
                focus_seq=max(1, 1_000_000 - focus_history),
                identifier=address,
                visible=visible,
                on_screen=visible,
            )
            windows.append(window)
            self.windows[window.id] = window
            self.addresses[window.id] = address

        if not active_id:
            active_id = next((win.id for win in windows if win.focused), 0)

        return Snapshot(
            outputs=outputs,
            windows=windows,
            active_ws=active_ws,
            focused_id=active_id,
        )

    def _dispatch(self, *args: str) -> None:
        result = run_command([self.binary, "dispatch", *args])
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            LOG.warning("hyprctl dispatch %s failed: %s", " ".join(args), detail)

    def spawn(self, command: str) -> None:
        self._dispatch("exec", command)

    def workspace(self, index: int, output: Optional[str]) -> None:
        if output:
            self._dispatch("focusmonitor", output)
        self._dispatch("workspace", str(index))

    def focus(self, window_id: int) -> None:
        window = self.windows.get(window_id)
        if window is None:
            LOG.warning("window %s is no longer present", window_id)
            return
        if window.output:
            self._dispatch("focusmonitor", window.output)
        if window.ws > 0:
            self._dispatch("workspace", str(window.ws))
        address = self.addresses.get(window_id)
        if address:
            self._dispatch("focuswindow", f"address:{address}")

    def close(self, window_id: int) -> None:
        address = self.addresses.get(window_id)
        if not address:
            LOG.warning("window %s is no longer present", window_id)
            return
        self._dispatch("closewindow", f"address:{address}")


class NiriAdapter(Adapter):
    name = "niri"

    def __init__(self, binary: str = "niri") -> None:
        self.binary = binary
        self.windows: dict[int, WindowInfo] = {}

    def _json(self, what: str) -> Any:
        return json_command([self.binary, "msg", "--json", what])

    def query(self) -> Snapshot:
        outputs_raw = self._json("outputs")
        workspaces_raw = self._json("workspaces")
        windows_raw = self._json("windows")
        if isinstance(outputs_raw, dict):
            outputs_iter = list(outputs_raw.values())
        elif isinstance(outputs_raw, list):
            outputs_iter = outputs_raw
        else:
            outputs_iter = []
        if not isinstance(workspaces_raw, list):
            workspaces_raw = []
        if not isinstance(windows_raw, list):
            windows_raw = []

        workspaces: list[dict[str, Any]] = [
            ws for ws in workspaces_raw if isinstance(ws, dict) and ws.get("id") is not None
        ]
        by_workspace_id = {as_int(ws.get("id"), -1): ws for ws in workspaces}

        outputs: list[OutputInfo] = []
        for output in outputs_iter:
            if not isinstance(output, dict):
                continue
            name = str(output.get("name", "") or "")
            logical = output.get("logical")
            if not name or not isinstance(logical, dict):
                continue
            active = next(
                (ws for ws in workspaces if ws.get("output") == name and ws.get("is_active")),
                None,
            )
            outputs.append(
                OutputInfo(
                    name=name,
                    make=str(output.get("make", "") or ""),
                    model=str(output.get("model", "") or ""),
                    serial=str(output.get("serial", "") or ""),
                    x=as_int(logical.get("x")),
                    y=as_int(logical.get("y")),
                    width=as_int(logical.get("width")),
                    height=as_int(logical.get("height")),
                    ws=max(1, as_int(active.get("idx") if active else 1, 1)),
                    focused=False,
                    layout="niri",
                )
            )
        by_output = {out.name: out for out in outputs}

        focused_ws = next((ws for ws in workspaces if ws.get("is_focused")), None)
        focused_output_name = str(focused_ws.get("output", "") or "") if focused_ws else ""
        if not focused_output_name and outputs:
            focused_output_name = outputs[0].name
        for output in outputs:
            output.focused = output.name == focused_output_name
        active_ws = as_int(focused_ws.get("idx") if focused_ws else 1, 1)
        if not focused_ws:
            focused_output = by_output.get(focused_output_name)
            active_ws = focused_output.ws if focused_output else 1

        windows: list[WindowInfo] = []
        self.windows.clear()
        focused_id = 0
        for window in windows_raw:
            if not isinstance(window, dict):
                continue
            window_id = as_int(window.get("id"), 0)
            workspace_id = window.get("workspace_id")
            if window_id <= 0 or workspace_id is None:
                continue
            workspace = by_workspace_id.get(as_int(workspace_id), None)
            if workspace is None:
                continue
            ws = as_int(workspace.get("idx"), 0)
            if ws <= 0:
                continue
            output_name = str(workspace.get("output", "") or "")
            output = by_output.get(output_name)
            layout = window.get("layout") or {}
            position = layout.get("tile_pos_in_workspace_view")
            size = layout.get("tile_size") or layout.get("window_size") or (0, 0)
            width, height = as_pair(size)
            if position and output is not None:
                x = output.x + int(round(float(position[0])))
                y = output.y + int(round(float(position[1])))
                on_screen = bool(workspace.get("is_active"))
            else:
                x = 0
                y = 0
                on_screen = False
            visible = bool(workspace.get("is_active"))
            focused = bool(window.get("is_focused", False))
            if focused:
                focused_id = window_id
            timestamp = window.get("focus_timestamp") or {}
            if isinstance(timestamp, dict):
                focus_seq = as_int(timestamp.get("secs"), 0) * 1_000_000_000 + as_int(
                    timestamp.get("nanos"), 0
                )
            else:
                focus_seq = 0
            entry = WindowInfo(
                id=window_id,
                ws=ws,
                focused=focused,
                floating=bool(window.get("is_floating", False)),
                fullscreen=False,
                app_id=str(window.get("app_id", "") or ""),
                title=str(window.get("title", "") or ""),
                output=output_name,
                x=x,
                y=y,
                width=width,
                height=height,
                focus_seq=focus_seq,
                identifier=str(window_id),
                visible=visible,
                on_screen=on_screen,
            )
            windows.append(entry)
            self.windows[entry.id] = entry

        return Snapshot(
            outputs=outputs,
            windows=windows,
            active_ws=active_ws,
            focused_id=focused_id,
        )

    def _action(self, *args: str) -> None:
        result = run_command([self.binary, "msg", "action", *args])
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            LOG.warning("niri action %s failed: %s", " ".join(args), detail)

    def spawn(self, command: str) -> None:
        self._action("spawn-sh", "--", command)

    def workspace(self, index: int, output: Optional[str]) -> None:
        if output:
            self._action("focus-monitor", output)
        self._action("focus-workspace", str(index))

    def focus(self, window_id: int) -> None:
        window = self.windows.get(window_id)
        if window is None:
            LOG.warning("window %s is no longer present", window_id)
            return
        if window.output:
            self._action("focus-monitor", window.output)
        if window.ws > 0:
            self._action("focus-workspace", str(window.ws))
        self._action("focus-window", "--id", str(window_id))

    def close(self, window_id: int) -> None:
        if window_id not in self.windows:
            LOG.warning("window %s is no longer present", window_id)
            return
        self._action("close-window", "--id", str(window_id))


def detect_compositor() -> str:
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
        return "hyprland"
    if os.environ.get("NIRI_SOCKET") and shutil.which("niri"):
        return "niri"
    if shutil.which("hyprctl"):
        try:
            HyprlandAdapter("hyprctl").query()
            return "hyprland"
        except CompatError as exc:
            LOG.debug("Hyprland probe failed: %s", exc)
    if shutil.which("niri"):
        try:
            NiriAdapter("niri").query()
            return "niri"
        except CompatError as exc:
            LOG.debug("Niri probe failed: %s", exc)
    raise CompatError(
        "cannot detect Hyprland or Niri; pass --compositor hyprland or --compositor niri"
    )


def make_adapter(name: str) -> Adapter:
    if name == "hyprland":
        if not shutil.which("hyprctl"):
            raise CompatError("hyprctl was not found in PATH")
        return HyprlandAdapter("hyprctl")
    if name == "niri":
        if not shutil.which("niri"):
            raise CompatError("niri was not found in PATH")
        return NiriAdapter("niri")
    raise CompatError(f"unsupported compositor: {name}")


def default_socket_path() -> str:
    configured = os.environ.get("TESSA_IPC")
    if configured:
        return configured
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        return os.path.join(runtime, "tessa.sock")
    uid = getattr(os, "getuid", lambda: 0)()
    return f"/tmp/tessa-panel-compat-{uid}.sock"


@dataclass
class PanelProc:
    output: str
    proc: subprocess.Popen[bytes]
    started: float


class Bridge:
    def __init__(
        self,
        adapter: Adapter,
        socket_path: str,
        panel_bin: str,
        spawn_panels: bool,
        poll_interval: float,
    ) -> None:
        self.adapter = adapter
        self.socket_path = socket_path
        self.panel_bin = panel_bin
        self.spawn_panels = spawn_panels
        self.poll_interval = max(0.15, poll_interval)
        self.selector = selectors.DefaultSelector()
        self.listener: Optional[socket.socket] = None
        self.clients: set[socket.socket] = set()
        self.buffers: dict[socket.socket, bytes] = {}
        self.snapshot = Snapshot()
        self.snapshot_bytes = b""
        self.panels: dict[str, PanelProc] = {}
        self.cooldowns: dict[str, float] = {}
        self.owner_output: Optional[str] = None
        self.running = False
        self.last_poll = 0.0
        self.panel_missing_logged = False

    def run(self) -> None:
        self._bind()
        self.running = True
        if threading.current_thread() is threading.main_thread():
            signal.signal(signal.SIGINT, self._on_signal)
            signal.signal(signal.SIGTERM, self._on_signal)
        try:
            self._refresh(initial=True)
            if self.spawn_panels:
                self._reconcile_panels()
            while self.running:
                now = time.monotonic()
                timeout = max(0.02, self.poll_interval - (now - self.last_poll))
                for key, _mask in self.selector.select(timeout):
                    if key.data == "listener":
                        self._accept()
                    else:
                        self._read_client(key.fileobj)
                if time.monotonic() - self.last_poll >= self.poll_interval:
                    self._refresh()
                if self.spawn_panels:
                    self._reap_panels()
                    self._reconcile_panels()
        finally:
            self._shutdown()

    def _on_signal(self, _signum: int, _frame: Any) -> None:
        self.running = False

    def _bind(self) -> None:
        path = self.socket_path
        if len(path) >= MAX_SOCKET_PATH:
            raise CompatError(f"IPC socket path is too long: {path}")
        if os.path.exists(path):
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                probe.settimeout(0.2)
                probe.connect(path)
            except OSError:
                os.unlink(path)
            else:
                raise CompatError(f"another process is already listening on {path}")
            finally:
                probe.close()
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(path)
        os.chmod(path, 0o600)
        listener.listen(16)
        listener.setblocking(False)
        self.listener = listener
        self.selector.register(listener, selectors.EVENT_READ, "listener")
        LOG.info("listening on %s", path)

    def _accept(self) -> None:
        assert self.listener is not None
        while True:
            try:
                conn, _ = self.listener.accept()
            except BlockingIOError:
                return
            except OSError as exc:
                LOG.warning("accept failed: %s", exc)
                return
            conn.settimeout(3.0)
            self.clients.add(conn)
            self.buffers[conn] = b""
            self.selector.register(conn, selectors.EVENT_READ, "client")
            LOG.debug("panel connected")
            if self.snapshot_bytes:
                self._send(conn, self.snapshot_bytes)

    def _read_client(self, conn: socket.socket) -> None:
        try:
            chunk = conn.recv(65536)
        except BlockingIOError:
            return
        except OSError:
            self._drop(conn)
            return
        if not chunk:
            self._drop(conn)
            return
        data = self.buffers.get(conn, b"") + chunk
        while b"\n" in data:
            raw, data = data.split(b"\n", 1)
            line = raw.decode("utf-8", "replace").rstrip("\r")
            self._handle_line(conn, line)
        self.buffers[conn] = data

    def _handle_line(self, conn: socket.socket, line: str) -> None:
        if line.startswith("CMD "):
            self._handle_command(line[4:].strip())
        elif line.startswith("SEND "):
            self._send_event(line[5:].strip())

    def _handle_command(self, command: str) -> None:
        if not command:
            return
        if command == "subscribe all":
            self._send_snapshot()
            return
        if command.startswith("spawn "):
            self.adapter.spawn(command[6:].strip())
            self._refresh()
            return
        if command.startswith("workspace "):
            parts = command.split()
            if len(parts) >= 2:
                index = as_int(parts[1], 0)
                if index > 0:
                    output = parts[2] if len(parts) >= 3 else None
                    self.adapter.workspace(index, output)
                    self._refresh()
            return
        if command.startswith(("activate ", "focus ", "close ")):
            action, _, raw_id = command.partition(" ")
            window_id = as_int(raw_id.strip(), 0)
            if window_id > 0:
                if action == "activate" or action == "focus":
                    self.adapter.focus(window_id)
                else:
                    self.adapter.close(window_id)
                self._refresh()
            return
        if command == "quit":
            LOG.info("ignoring CMD quit: the compat bridge never stops the host compositor")
            return
        if command.startswith("extension-enable"):
            LOG.debug("ignoring Tessa extension command: %s", command)
            return
        LOG.debug("ignoring unsupported command: %s", command)

    def _send_event(self, spec: str) -> None:
        if not spec:
            return
        if spec.startswith("panel:"):
            spec = spec.split(":", 1)[1]
        if spec == "launcher" or spec.startswith("launcher:"):
            line = "EVENT\tlauncher"
            if ":" in spec:
                line += "\targ=" + escape(spec.split(":", 1)[1])
        else:
            line = "EVENT\tpanel\targ=" + escape(spec)
        payload = (line + "\n").encode("utf-8")
        LOG.info("event: %s", line)
        self._broadcast(payload)

    def _send_snapshot(self) -> None:
        if self.snapshot_bytes:
            self._broadcast(self.snapshot_bytes)

    def _send(self, conn: socket.socket, payload: bytes) -> None:
        try:
            conn.sendall(payload)
        except OSError:
            self._drop(conn)

    def _broadcast(self, payload: bytes) -> None:
        for conn in list(self.clients):
            self._send(conn, payload)

    def _drop(self, conn: socket.socket) -> None:
        if conn in self.clients:
            self.clients.discard(conn)
            self.buffers.pop(conn, None)
            try:
                self.selector.unregister(conn)
            except (KeyError, ValueError):
                pass
            try:
                conn.close()
            except OSError:
                pass
            LOG.debug("panel disconnected")

    def _refresh(self, initial: bool = False) -> None:
        self.last_poll = time.monotonic()
        try:
            snapshot = self.adapter.query()
        except CompatError as exc:
            if initial:
                raise
            LOG.warning("state query failed: %s", exc)
            return
        payload = snapshot.serialize()
        if initial or payload != self.snapshot_bytes:
            self.snapshot = snapshot
            self.snapshot_bytes = payload
            if initial:
                LOG.info(
                    "state: %d outputs, %d windows, active workspace %d",
                    len(snapshot.outputs),
                    len(snapshot.windows),
                    snapshot.active_ws,
                )
            self._broadcast(payload)

    def _reap_panels(self) -> None:
        now = time.monotonic()
        for name, panel in list(self.panels.items()):
            code = panel.proc.poll()
            if code is None:
                continue
            LOG.warning("panel for %s exited with status %s", name, code)
            self.panels.pop(name, None)
            self.cooldowns[name] = now + 1.0

    def _reconcile_panels(self) -> None:
        if not self.spawn_panels or not self.snapshot.outputs:
            return
        outputs = [out for out in self.snapshot.outputs if out.name]
        owner = outputs[0].name if outputs else None
        if owner != self.owner_output:
            if self.owner_output is not None:
                LOG.info("panel owner changed to %s; restarting panels", owner)
                for name in list(self.panels):
                    self._stop_panel(name)
            self.owner_output = owner

        names = {out.name for out in outputs}
        for name in list(self.panels):
            if name not in names:
                self._stop_panel(name)

        if not shutil.which(self.panel_bin):
            if not self.panel_missing_logged:
                LOG.error("panel binary not found: %s", self.panel_bin)
                self.panel_missing_logged = True
            return

        now = time.monotonic()
        for output in outputs:
            if output.name in self.panels:
                continue
            if now < self.cooldowns.get(output.name, 0.0):
                continue
            self._spawn_panel(output)

    def _spawn_panel(self, output: OutputInfo) -> None:
        env = os.environ.copy()
        env["TESSA_IPC"] = self.socket_path
        env["TESSA_PANEL_OUTPUT"] = output.name
        if output.make:
            env["TESSA_PANEL_OUTPUT_MAKE"] = output.make
        if output.model:
            env["TESSA_PANEL_OUTPUT_MODEL"] = output.model
        if output.serial:
            env["TESSA_PANEL_OUTPUT_SERIAL"] = output.serial
        owner = "1" if output.name == self.owner_output else "0"
        env["TESSA_PANEL_NOTIFY_OWNER"] = owner
        env["TESSA_PANEL_SYSTEM_OWNER"] = owner
        try:
            proc = subprocess.Popen([self.panel_bin], env=env)
        except OSError as exc:
            LOG.error("cannot start panel for %s: %s", output.name, exc)
            self.cooldowns[output.name] = time.monotonic() + 2.0
            return
        self.panels[output.name] = PanelProc(output.name, proc, time.monotonic())
        LOG.info("panel started for %s (pid %d)", output.name, proc.pid)

    def _stop_panel(self, name: str) -> None:
        panel = self.panels.pop(name, None)
        if panel is None:
            return
        LOG.info("stopping panel for %s (pid %d)", name, panel.proc.pid)
        if panel.proc.poll() is None:
            panel.proc.terminate()
            try:
                panel.proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                panel.proc.kill()
                try:
                    panel.proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    pass

    def _shutdown(self) -> None:
        for conn in list(self.clients):
            self._drop(conn)
        if self.listener is not None:
            try:
                self.selector.unregister(self.listener)
            except (KeyError, ValueError):
                pass
            self.listener.close()
            self.listener = None
        for name in list(self.panels):
            self._stop_panel(name)
        try:
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
        except OSError:
            pass
        self.selector.close()
        LOG.info("stopped")


def send_control(socket_path: str, spec: str) -> int:
    if len(socket_path) >= MAX_SOCKET_PATH:
        print(f"tessa-panel-compat: socket path is too long: {socket_path}", file=sys.stderr)
        return 1
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(2.0)
        client.connect(socket_path)
        client.sendall(("SEND " + spec + "\n").encode("utf-8"))
    except OSError as exc:
        print(f"tessa-panel-compat: cannot reach {socket_path}: {exc}", file=sys.stderr)
        return 1
    finally:
        client.close()
    return 0


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run tessa-panel against Hyprland or Niri through a Tessa IPC compatibility bridge."
    )
    parser.add_argument(
        "--compositor",
        choices=("auto", "hyprland", "niri"),
        default="auto",
        help="host compositor (default: auto-detect)",
    )
    parser.add_argument(
        "--socket",
        default=None,
        help="bridge IPC socket (default: $TESSA_IPC or $XDG_RUNTIME_DIR/tessa.sock)",
    )
    parser.add_argument(
        "--panel",
        default=os.environ.get("TESSA_PANEL_BIN", "tessa-panel"),
        help="tessa-panel executable (default: $TESSA_PANEL_BIN or tessa-panel)",
    )
    parser.add_argument(
        "--poll",
        type=float,
        default=0.75,
        help="compositor state poll interval in seconds (default: 0.75)",
    )
    parser.add_argument(
        "--no-spawn",
        action="store_true",
        help="serve state without starting tessa-panel processes",
    )
    parser.add_argument(
        "--print-state",
        action="store_true",
        help="print one translated state snapshot and exit",
    )
    parser.add_argument(
        "--send",
        metavar="TARGET",
        default=None,
        help="send an event to running panels (launcher, switcher, control, ...)",
    )
    parser.add_argument("--verbose", action="store_true", help="enable debug logging")
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="tessa-panel-compat: %(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    socket_path = args.socket or default_socket_path()

    if args.send:
        return send_control(socket_path, args.send)

    try:
        compositor = args.compositor
        if compositor == "auto":
            compositor = detect_compositor()
            LOG.info("detected %s", compositor)
        adapter = make_adapter(compositor)
        if args.print_state:
            sys.stdout.buffer.write(adapter.query().serialize())
            return 0
        bridge = Bridge(
            adapter=adapter,
            socket_path=socket_path,
            panel_bin=args.panel,
            spawn_panels=not args.no_spawn,
            poll_interval=args.poll,
        )
        bridge.run()
        return 0
    except CompatError as exc:
        LOG.error("%s", exc)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
