#!/bin/bash
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

# This script prepares a standard qcow2 appliance for Firecracker.
# It converts the image to raw and provides instructions for further manual steps.

INPUT_IMAGE=$1
OUTPUT_IMAGE=${2:-$(basename "${INPUT_IMAGE%.*}").raw}

if [ -z "$INPUT_IMAGE" ]; then
    echo "Usage: $0 <input_image.qcow2> [<output_image.raw>]"
    exit 1
fi

if ! command -v qemu-img &> /dev/null; then
    echo "Error: qemu-img is required."
    exit 1
fi

echo "Converting $INPUT_IMAGE to $OUTPUT_IMAGE..."
qemu-img convert -O raw "$INPUT_IMAGE" "$OUTPUT_IMAGE"

echo "Successfully converted to raw image."
echo ""
echo "NEXT STEPS (Requires root privileges):"
echo "1. Run '/usr/sbin/fdisk -l $OUTPUT_IMAGE' to identify the root partition."
echo "2. Use './tools/extract_firecracker_assets.py $INPUT_IMAGE' to extract the kernel and initrd."
echo "   Note: Firecracker requires an UNCOMPRESSED kernel (vmlinux, not vmlinuz)."
echo "3. If using MicroOS, determine the correct rootflags (e.g., subvol=@/root)."
echo ""
echo "Example BACKEND_FIRECRACKER_BOOTARGS for MicroOS:"
echo "  root=/dev/vda2 rootflags=subvol=@/root console=ttyS0 reboot=k panic=1 pci=off"
