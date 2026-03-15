# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import subprocess
from .log import diag


class Backend:
    def __init__(self, name="qemu"):
        self.name = name
        self.process = None

    def start(self):
        diag(f"Starting backend: {self.name}")
        # In a real implementation, this would spawn QEMU or similar
        return True

    def stop(self):
        if self.process:
            diag(f"Stopping backend: {self.name}")
            self.process.terminate()
            self.process = None

    def save_memory_dump(self, filename: str):
        diag(f"Saving memory dump to {filename}")
        return True
