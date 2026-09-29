#!/usr/bin/env python3
# Minimal org.kde.klipper shim for non-Plasma compositors (niri, etc).
#
# Kiview (flatpak) talks to Klipper for ALL its clipboard round-trips,
# even when given an explicit file path. Real Klipper only exists on Plasma,
# so without it Kiview dies with "The name is not activatable".
# This shim owns org.kde.klipper and backs get/setClipboardContents
# with wl-paste/wl-copy. Text (incl. copied file URLs) round-trips fine;
# file:// content is restored with the text/uri-list mimetype so copied
# files stay pastable. Image-only clipboards can't survive a text-only
# API and may be downgraded while a preview is open.
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.kde.klipper"
OBJ_PATH = "/klipper"
IFACE = "org.kde.klipper.klipper"

INTROSPECTION = f"""<node>
  <interface name="{IFACE}">
    <method name="getClipboardContents">
      <arg type="s" name="contents" direction="out"/>
    </method>
    <method name="setClipboardContents">
      <arg type="s" name="contents" direction="in"/>
    </method>
  </interface>
</node>"""

GET_ORDER = [
    "text/plain;charset=utf-8",
    "text/plain",
    "UTF8_STRING",
    "STRING",
    "TEXT",
    "text/uri-list",
]


def wl_paste(mime=None):
    cmd = ["wl-paste"] if mime is None else ["wl-paste", "--type", mime]
    try:
        out = subprocess.run(
            cmd, capture_output=True, timeout=3, check=False
        ).stdout.decode("utf-8", errors="replace")
        return out
    except (subprocess.SubprocessError, OSError):
        return ""


def get_clipboard_contents():
    # exact default first (whatever the owner prefers as text)
    text = wl_paste()
    if not text:
        for mime in GET_ORDER:
            text = wl_paste(mime)
            if text:
                break
    # Dolphin's copy_location appends a trailing newline; Kiview checks
    # the string with exists() verbatim, so "path\n" is invalid.
    # (Real Klipper doesn't hand back the newline either.)
    # Strip only \r\n — a filename may legitimately end with a space.
    return text.rstrip("\r\n") if text else ""


def set_clipboard_contents(text):
    try:
        if text and all(
            line.startswith("file://") for line in text.splitlines() if line.strip()
        ):
            subprocess.run(
                ["wl-copy", "-t", "text/uri-list"],
                input=text.encode(), timeout=3, check=False,
            )
        else:
            subprocess.run(
                ["wl-copy"], input=text.encode(), timeout=3, check=False
            )
    except (subprocess.SubprocessError, OSError):
        pass


def on_method_call(conn, sender, path, iface, method, params, invocation):
    if method == "getClipboardContents":
        invocation.return_value(GLib.Variant("(s)", (get_clipboard_contents(),)))
    elif method == "setClipboardContents":
        (text,) = params.unpack()
        set_clipboard_contents(text)
        invocation.return_value(None)
    else:
        invocation.return_error_literal(
            Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD,
            f"Unknown method {method}",
        )


def on_bus_acquired(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    conn.register_object(
        OBJ_PATH, node.interfaces[0], on_method_call, None, None,
    )
    print(f"shim: owning {BUS_NAME}", flush=True)


def on_name_lost(conn, name):
    print("shim: lost bus name, exiting", flush=True)
    sys.exit(1)


Gio.bus_own_name(
    Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
    on_bus_acquired, lambda c, n: None, on_name_lost,
)
GLib.MainLoop().run()
