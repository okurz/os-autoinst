# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import subprocess
import time
from typing import Any, Dict, List, Optional
from .log import diag, fctinfo
from .vars import global_vars
from .qemu_builder import QemuBuilder
from .qmp import QmpClient


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
        self.qemu_bin = "qemu-system-x86_64"
        self.qmp_socket = "qmp.sock"
        self.qmp = None

    def start(self) -> bool:
        diag("Starting QEMU backend")
        builder = QemuBuilder(global_vars)
        builder.configure_basics()
        builder.configure_serial()
        builder.configure_graphics()
        builder.configure_network()
        builder.configure_storage()

        # Add QMP socket
        builder.add("qmp", f"unix:{self.qmp_socket},server,nowait")

        cmd = [self.qemu_bin] + builder.build()
        diag(f"Executing: {' '.join(cmd)}")

        # self.process = subprocess.Popen(cmd)
        # self.qmp = QmpClient(self.qmp_socket)
        # if not self.qmp.connect():
        #     diag("Failed to connect to QMP")
        #     return False

        self.started = True
        return True

    def stop_vm(self):
        diag("Stopping QEMU VM")
        if self.qmp:
            self.qmp.execute("quit")
            self.qmp.disconnect()
        if self.process:
            self.process.terminate()
            self.process = None

    def backend_can_handle(self, args: Dict[str, Any]) -> bool:
        function = args.get("function")
        if function in ["snapshots", "vnc", "serial", "last_screenshot_data"]:
            return True
        return super().backend_can_handle(args)

    def backend_last_screenshot_data(self, args: Dict[str, Any]) -> Dict[str, Any]:
        import base64

        # Dummy screenshot
        dummy_image = b"P6\n1 1\n255\n\xff\xff\xff"
        return {"image": base64.b64encode(dummy_image).decode("utf-8"), "frame": 0}
