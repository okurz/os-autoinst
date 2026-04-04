#!/bin/bash
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

# This script builds a Firecracker rootfs image from a Dockerfile.
# Requires: podman, mkfs.ext4

IMG_SIZE=${IMG_SIZE:-512M}
ROOTFS_IMG=${ROOTFS_IMG:-rootfs.ext4}
DOCKER_CONTEXT="$(dirname "$0")/../container/firecracker_rootfs"

if ! command -v podman &> /dev/null; then
    echo "Error: podman is required."
    exit 1
fi

if ! command -v mkfs.ext4 &> /dev/null; then
    echo "Error: mkfs.ext4 (e2fsprogs) is required."
    exit 1
fi

echo "Building Firecracker rootfs image: $ROOTFS_IMG from $DOCKER_CONTEXT"

# Build the container image
podman build -t os-autoinst-firecracker-rootfs "$DOCKER_CONTEXT"

# Export the container filesystem to a raw ext4 image
echo "Creating ext4 image file..."
truncate -s "$IMG_SIZE" "$ROOTFS_IMG"
mkfs.ext4 -F "$ROOTFS_IMG"

# Populate the image
echo "Populating image..."
TEMP_CONTAINER="fc-export-$$"
podman create --name $TEMP_CONTAINER os-autoinst-firecracker-rootfs
mkdir -p mnt

# Note: Loop mounting usually requires root privileges.
# In a CI environment (e.g., GitHub Actions or OBS), this is typically available.
# Alternatively, tools like 'guestfish' or 'genext2fs' can be used for unprivileged image creation.
if [ "$(id -u)" -eq 0 ]; then
    mount -o loop "$ROOTFS_IMG" mnt
    podman export "$TEMP_CONTAINER" | tar -xf - -C mnt
    umount mnt
else
    echo "Warning: Not running as root. Attempting 'podman unshare' (might fail if loop-mount is restricted)..."
    podman unshare bash -c "
      mount -o loop $ROOTFS_IMG mnt || (echo 'Loop mount failed. Please run as root or use guestfish.'; exit 1)
      podman export $TEMP_CONTAINER | tar -xf - -C mnt
      umount mnt
    "
fi

# Clean up
rm -rf mnt
podman rm -f $TEMP_CONTAINER

echo "Successfully built $ROOTFS_IMG"
