# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import socket
import json
import time
from typing import Any, Dict, Optional
from .log import diag


class QmpClient:
    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self.sock = None

    def connect(self, timeout: float = 10.0):
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.socket_path)
                # Read greeting
                greeting = self._read_json()
                # Negotiate capabilities
                self.execute("qmp_capabilities")
                return True
            except (ConnectionRefusedError, FileNotFoundError):
                time.sleep(0.1)
        return False

    def disconnect(self):
        if self.sock:
            self.sock.close()
            self.sock = None

    def execute(self, command: str, arguments: Optional[Dict[str, Any]] = None) -> Any:
        if not self.sock:
            return None

        cmd = {"execute": command}
        if arguments:
            cmd["arguments"] = arguments

        self.sock.sendall(json.dumps(cmd).encode() + b"\n")
        return self._read_json()

    def _read_json(self) -> Any:
        # Simple line-based JSON reader
        buffer = b""
        while True:
            chunk = self.sock.recv(1)
            if not chunk:
                break
            buffer += chunk
            if chunk == b"\n":
                break
        if not buffer:
            return None
        return json.loads(buffer.decode())
