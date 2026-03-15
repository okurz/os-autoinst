# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import socket
import struct
from .log import diag


class Console:
    def __init__(self, name: str):
        self.name = name

    def activate(self):
        diag(f"Activating console: {self.name}")


class VNCConsole(Console):
    def __init__(self, name: str, hostname: str, port: int):
        super().__init__(name)
        self.hostname = hostname
        self.port = port
        self.socket = None
        self.width = 0
        self.height = 0

    def activate(self):
        super().activate()
        diag(f"Connecting to VNC at {self.hostname}:{self.port}")
        try:
            self.socket = socket.create_connection(
                (self.hostname, self.port), timeout=5
            )
            self._handshake()
        except Exception as e:
            diag(f"VNC connection failed: {e}")
            if self.socket:
                self.socket.close()
            self.socket = None

    def _handshake(self):
        # RFB protocol version
        diag("VNC Handshake: waiting for version")
        ver_data = self.socket.recv(12)
        diag(f"VNC Server version: {ver_data.decode().strip()}")
        self.socket.sendall(b"RFB 003.008\n")

        # Security types
        diag("VNC Handshake: waiting for security types")
        sec_types = self.socket.recv(1)
        num_types = sec_types[0]
        types = self.socket.recv(num_types)
        diag(f"VNC Server security types: {list(types)}")

        # Select 'None' (1) if available, else fail for now
        if 1 in types:
            diag("VNC Handshake: selecting 'None' security")
            self.socket.sendall(b"\x01")
        else:
            diag("VNC Only supports security types we don't handle yet")
            return

        # Security result
        diag("VNC Handshake: waiting for security result")
        res = self.socket.recv(4)
        if struct.unpack(">I", res)[0] != 0:
            diag("VNC Security failed")
            return

        # Client init
        diag("VNC Handshake: sending client init")
        self.socket.sendall(b"\x01")  # Shared-flag

        # Server init
        diag("VNC Handshake: waiting for server init")
        server_init = self.socket.recv(24)
        self.width, self.height = struct.unpack(">HH", server_init[0:4])
        diag(f"VNC Desktop size: {self.width}x{self.height}")

        # Name
        name_len = struct.unpack(">I", server_init[20:24])[0]
        if name_len > 0:
            name = self.socket.recv(name_len)
            diag(f"VNC Desktop name: {name.decode()}")

    def send_key(self, key_code: int, down: bool) -> bool:
        if not self.socket:
            return False
        try:
            # KeyEvent message (type 4)
            # 1 byte type, 1 byte down-flag, 2 bytes padding, 4 bytes keysym
            data = struct.pack(">BBHI", 4, 1 if down else 0, 0, key_code)
            self.socket.sendall(data)
            return True
        except Exception:
            return False


# Common X11 keysyms used in VNC
KEY_MAP = {
    "esc": 0xFF1B,
    "ret": 0xFF0D,
    "tab": 0xFF09,
    "backspace": 0xFF08,
    "up": 0xFF52,
    "down": 0xFF54,
    "left": 0xFF51,
    "right": 0xFF53,
    "pgup": 0xFF55,
    "pgdn": 0xFF56,
    "home": 0xFF50,
    "end": 0xFF57,
}


def get_keysym(key: str) -> int:
    if len(key) == 1:
        return ord(key)
    return KEY_MAP.get(key.lower(), 0)
