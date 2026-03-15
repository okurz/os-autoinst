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

        # SMP
        cpus = self.vars.get("QEMUCPUS")
        if cpus:
            smp = [str(cpus)]
            for key in ["SOCKETS", "DIES", "CLUSTERS", "CORES", "THREADS"]:
                val = self.vars.get(f"QEMU{key}")
                if val:
                    smp.append(f"{key.lower()}={val}")
            self.add("smp", ",".join(smp))

        if not self.vars.get("QEMU_NO_KVM") and os.access("/dev/kvm", os.R_OK):
            self.add("enable-kvm")

        self.add("no-shutdown")
        self.add("S")

    def configure_serial(self):
        # Default serial setup
        self.add("chardev", "ringbuf,id=serial0,logfile=serial0,logappend=on")
        self.add("serial", "chardev:serial0")

    def configure_graphics(self):
        vnc = self.vars.get("VNC")
        if vnc:
            vnc = str(vnc)
            vnc_str = vnc if ":" in vnc else f":{vnc}"
            vnc_str += ",share=force-shared"
            extra = self.vars.get("VNC_EXTRA_VARS")
            if extra:
                vnc_str += f",{extra}"
            self.add("vnc", vnc_str)

            vnckb = self.vars.get("VNCKB")
            if vnckb:
                self.add("k", vnckb)
        else:
            self.add("vga", "std")

    def configure_network(self):
        if self.vars.get("OFFLINE_SUT"):
            self.add("net", "none")
            return

        # Simplified networking: single user NIC for now
        nic_model = self.vars.get("NICMODEL", "virtio-net-pci")
        mac = self.vars.get("NICMAC", "52:54:00:12:34:56")

        self.add("netdev", "user,id=qanet0")
        self.add("device", f"{nic_model},netdev=qanet0,mac={mac}")

    def configure_storage(self):
        num_disks = int(self.vars.get("NUMDISKS", 1))
        hdd_model = self.vars.get("HDDMODEL", "virtio-blk-pci")

        for i in range(num_disks):
            hdd = self.vars.get(f"HDD_{i}")
            if hdd:
                self.add("drive", f"file={hdd},format=qcow2,if=none,id=drive-hdd{i}")
                self.add("device", f"{hdd_model},drive=drive-hdd{i},id=hdd{i}")

        iso = self.vars.get("ISO")
        if iso:
            cd_model = self.vars.get("CDMODEL", "scsi-cd")
            if "scsi" in cd_model:
                self.add("device", "virtio-scsi-pci,id=scsi0")
            # Assuming a default SCSI controller if scsi-cd is used
            self.add("drive", f"file={iso},format=raw,if=none,id=drive-cd0,media=cdrom")
            self.add("device", f"{cd_model},drive=drive-cd0,id=cd0")

    def configure_boot(self):
        boot = []
        bootfrom = self.vars.get("BOOTFROM")
        if bootfrom:
            boot.append(f"order={bootfrom}")

        menu = self.vars.get("BOOT_MENU")
        if menu:
            boot.append("menu=on")

        if boot:
            self.add("boot", ",".join(boot))

        for attr in ["KERNEL", "INITRD", "APPEND"]:
            val = self.vars.get(attr)
            if val:
                self.add(attr.lower(), val)
