# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
FROM registry.opensuse.org/opensuse/bci/bci-base:latest

# Install Perl and minimal dependencies for autotest
RUN zypper -n install perl-base perl-Mojo-IOLoop-ReadWriteProcess \
    perl-Mojolicious perl-JSON-PP perl-YAML-LibYAML perl-IO-Socket-SSL \
    squashfs kernel-default-base && \
    zypper clean -a

# Ensure root user has a password
RUN echo "root:root" | chpasswd

CMD ["/bin/sh"]
