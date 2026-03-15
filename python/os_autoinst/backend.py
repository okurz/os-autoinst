# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import subprocess
import time
from typing import Any, Dict, List, Optional
from .log import diag, fctinfo
from .vars import global_vars


class Backend:
    def __init__(self):
        self.started = False
        self.serialfile = "serial0"
        self.serial_offset = 0
        self.xres = global_vars.get("XRES", 1024)
        self.yres = global_vars.get("YRES", 768)
        self.children = []

    def start(self) -> bool:
        diag(f"Starting backend base")
        self.started = True
        return True

    def stop(self):
        diag("Stopping backend")
        self.stop_vm()
        self.started = False

    def stop_vm(self):
        # To be overridden by subclasses (e.g. Qemu)
        pass

    def check_alive(self) -> bool:
        return self.started

    def handle_command(self, cmd: str, args: Dict[str, Any]) -> Any:
        method_name = f"backend_{cmd}"
        if hasattr(self, method_name):
            method = getattr(self, method_name)
            return method(args)

        # Fallback to direct method name if not prefixed
        if hasattr(self, cmd):
            method = getattr(self, cmd)
            return method(args)

        diag(f"Backend does not support command: {cmd}")
        return None

    def backend_save_memory_dump(self, args: Dict[str, Any]) -> bool:
        filename = args.get("filename", "memory_dump")
        diag(f"Saving memory dump to {filename}")
        return True

    def backend_can_handle(self, args: Dict[str, Any]) -> bool:
        function = args.get("function")
        # Base class might not handle much
        return False


class QemuBackend(Backend):
    def __init__(self):
        super().__init__()
        self.name = "qemu"

    def start(self) -> bool:
        diag("Starting QEMU backend")
        # In a real implementation, this would build the QEMU command line
        # and use subprocess.Popen
        self.started = True
        return True

    def stop_vm(self):
        diag("Stopping QEMU VM")
        # Kill QEMU process here
        pass

    def backend_can_handle(self, args: Dict[str, Any]) -> bool:
        function = args.get("function")
        if function in ["snapshots", "vnc", "serial"]:
            return True
        return super().backend_can_handle(args)
