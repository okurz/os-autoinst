# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Install Perl and minimal dependencies for autotest
RUN zypper -n install perl-base perl-Mojo-IOLoop-ReadWriteProcess \
    perl-Mojolicious perl-JSON-XS perl-YAML-LibYAML perl-IO-Socket-SSL \
    perl-IPC-Run perl-IPC-System-Simple perl-Feature-Compat-Try \
    perl-Carp-Always perl-File-chdir perl-List-MoreUtils \
    perl-Net-DBus perl-Net-SNMP perl-Net-SSH2 perl-Socket-MsgHdr \
    perl-Time-Moment perl-XML-LibXML perl-XML-SemanticDiff \
    perl-YAML-PP perl-JSON-Validator \
    perl-Cpanel-JSON-XS perl-Crypt-DES perl-Exception-Class \
    perl-File-Map perl-Net-IP \
    squashfs kernel-default-base && \
    zypper clean -a

# Ensure root user has a password
RUN echo "root:root" | chpasswd

CMD ["/bin/sh"]
