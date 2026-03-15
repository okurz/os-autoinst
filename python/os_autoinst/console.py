# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import socket
import struct
from .log import diag

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
    "ins": 0xFF63,
    "del": 0xFFFF,
    "shift": 0xFFE1,
    "ctrl": 0xFFE3,
    "alt": 0xFFE9,
    "super": 0xFFEB,
    "equal": ord("="),
    "minus": ord("-"),
    "spc": ord(" "),
}


def get_keysym(key: str) -> int:
    if len(key) == 1:
        return ord(key)
    return KEY_MAP.get(key.lower(), 0)


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
        self.ikvm = False

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

        # SetPixelFormat (message type 0)
        # 32 bpp, 24 depth, little-endian, true-colour,
        # red-max 255, green-max 255, blue-max 255,
        # red-shift 16, green-shift 8, blue-shift 0
        pixel_format = struct.pack(
            ">BBBBCCCCnnnCCCxxx",
            0,  # type
            0,
            0,
            0,  # padding
            32,  # bpp
            24,  # depth
            0,  # big-endian
            1,  # true-colour
            255,
            255,
            255,  # max
            16,
            8,
            0,  # shift
            0,
            0,
            0,  # padding
        )
        self.socket.sendall(pixel_format)

        # SetEncodings (message type 2)
        # 0 = Raw
        encodings = struct.pack(">BBH", 2, 0, 1) + struct.pack(">i", 0)
        self.socket.sendall(encodings)

    def send_key(self, key_code: int, down: bool) -> bool:
        if not self.socket:
            return False
        try:
            # KeyEvent message (type 4)
            # 1 byte type, 1 byte down-flag, 2 bytes padding, 4 bytes keysym
            if self.ikvm:
                # Strange padding for ikvm mentioned in VNC.pm
                # pack('CxCnNx9', 4, $down_flag, 0, $key)
                data = struct.pack(">BxBHI9x", 4, 1 if down else 0, 0, key_code)
            else:
                data = struct.pack(">BBHI", 4, 1 if down else 0, 0, key_code)
            self.socket.sendall(data)
            return True
        except Exception:
            return False
