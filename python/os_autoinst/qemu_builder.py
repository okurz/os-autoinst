# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

from typing import List, Dict, Any, Optional
import os


class QemuBuilder:
    def __init__(self, vars_manager):
        self.vars = vars_manager
        self.params: List[List[str]] = []

    def add(self, key: str, value: Optional[str] = None):
        if value is not None:
            self.params.append([f"-{key}", str(value)])
        else:
            self.params.append([f"-{key}"])

    def build(self) -> List[str]:
        cmd = []
        for p in self.params:
            cmd.extend(p)
        return cmd

    def configure_basics(self):
        arch = self.vars.get("ARCH", "x86_64")

        ram = self.vars.get("QEMURAM")
        if ram:
            self.add("m", ram)

        machine = self.vars.get("QEMUMACHINE")
        if machine:
            self.add("machine", machine)

        cpu = self.vars.get("QEMUCPU")
        if cpu:
            self.add("cpu", cpu)

    def configure_serial(self):
        # Default serial setup
        self.add("chardev", "ringbuf,id=serial0,logfile=serial0,logappend=on")
        self.add("serial", "chardev:serial0")

    def configure_graphics(self):
        # Very basic stub for now
        self.add("vga", "std")
        self.add("vnc", ":0")

    def configure_network(self):
        # Very basic user networking stub
        self.add("netdev", "user,id=qanet0")
        self.add("device", "virtio-net-pci,netdev=qanet0,mac=52:54:00:12:34:56")

    def configure_storage(self):
        # Stub for block devices
        # In reality, this would look at HDD_0, HDD_1, etc.
        hdd = self.vars.get("HDD_0")
        if hdd:
            self.add("drive", f"file={hdd},format=qcow2,if=virtio")

        cdrom = self.vars.get("ISO")
        if cdrom:
            self.add("drive", f"file={cdrom},format=raw,if=ide,media=cdrom")
