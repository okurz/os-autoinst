# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import socket
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

    def activate(self):
        super().activate()
        diag(f"Connecting to VNC at {self.hostname}:{self.port}")
        # In a real implementation, this would handle RFB handshake
        # and start receiving updates.
