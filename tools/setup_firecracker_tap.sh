#!/bin/bash
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
set -e

# This script sets up a TAP interface for Firecracker MicroVMs.
# Requires: iproute2, sudo

TAP_DEV=${1:-tap0}
BRIDGE_DEV=${2:-br0}

if [ -z "$TAP_DEV" ]; then
    echo "Usage: $0 <tap_dev> [<bridge_dev>]"
    exit 1
fi

echo "Setting up TAP device: $TAP_DEV"

# Create TAP device
if ! ip link show "$TAP_DEV" &> /dev/null; then
    sudo ip tuntap add mode tap name "$TAP_DEV"
    sudo ip link set "$TAP_DEV" up
else
    echo "TAP device $TAP_DEV already exists."
fi

# Add to bridge if requested
if [ -n "$BRIDGE_DEV" ]; then
    # Create bridge if it doesn't exist
    if ! ip link show "$BRIDGE_DEV" &> /dev/null; then
        echo "Creating bridge device: $BRIDGE_DEV"
        sudo ip link add name "$BRIDGE_DEV" type bridge
        sudo ip link set "$BRIDGE_DEV" up
    fi
    sudo ip link set "$TAP_DEV" master "$BRIDGE_DEV"
fi

echo "Successfully set up $TAP_DEV (attached to ${BRIDGE_DEV:-none})"
