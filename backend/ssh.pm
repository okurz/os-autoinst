# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::ssh;

use Mojo::Base -strict, -signatures;

sub check_socket ($self, $fh, $write = undef) { $self->check_ssh_serial($fh) ? 1 $self->SUPER::check_socket($fh, $write) }

1;
