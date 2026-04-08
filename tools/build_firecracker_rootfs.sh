#!/bin/bash
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

# This script builds a Firecracker rootfs image from a Dockerfile.
# Requires: podman, mkfs.ext4

IMG_SIZE=${IMG_SIZE:-512M}
ROOTFS_IMG=${ROOTFS_IMG:-rootfs.ext4}
DOCKER_CONTEXT=${DOCKER_CONTEXT:-$(dirname "$0")/../container/firecracker_rootfs}
IMAGE_NAME=${IMAGE_NAME:-os-autoinst-firecracker-rootfs}

export PATH=$PATH:/usr/sbin:/sbin

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
podman build -t "$IMAGE_NAME" "$DOCKER_CONTEXT"

# Export the container filesystem to a raw ext4 image
echo "Creating ext4 image file..."
truncate -s "$IMG_SIZE" "$ROOTFS_IMG"
mkfs.ext4 -F "$ROOTFS_IMG"

# Populate the image
echo "Populating image..."
TEMP_CONTAINER="fc-export-$$"
podman create --name "$TEMP_CONTAINER" "$IMAGE_NAME"

if [ "$(id -u)" -eq 0 ]; then
    mkdir -p mnt
    mount -o loop "$ROOTFS_IMG" mnt
    podman export "$TEMP_CONTAINER" | tar -xf - -C mnt
    umount mnt
    rmdir mnt
elif command -v guestfish &> /dev/null; then
    echo "Using guestfish to populate image..."
    podman export "$TEMP_CONTAINER" > container_export.tar
    guestfish -a "$ROOTFS_IMG" -m /dev/sda << EOF
tar-in container_export.tar /
EOF
    rm container_export.tar
else
    echo "Error: Root privileges or guestfish required to populate image."
    podman rm -f "$TEMP_CONTAINER"
    exit 1
fi

podman rm -f "$TEMP_CONTAINER"

echo "Successfully built $ROOTFS_IMG"
