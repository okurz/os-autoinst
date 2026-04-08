# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
FROM registry.opensuse.org/opensuse/bci/bci-base:latest

# Install necessary tools for backend execution (ipmitool, ssh, etc.)
RUN zypper -n install ipmitool openssh-clients curl wget iproute2 tar && \
    zypper clean -a

# Ensure root user has a password for serial login if needed
RUN echo "root:root" | chpasswd

# Minimal init setup (if not using /bin/sh directly)
CMD ["/bin/sh"]
