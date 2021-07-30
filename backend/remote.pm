# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::remote;

use Mojo::Base 'backend::virt', -signatures;

use bmwqemu;
use IO::Select;


sub new ($class) {
    my $self = $class->SUPER::new;
    $bmwqemu::vars{WORKER_HOSTNAME} or die 'Undefined WORKER_HOSTNAME';
    return $self;
}

# only define the remote console - we leave the actual
# poweron to the test
sub do_start_vm ($self, @) {
    $self->truncate_serial_file;
    my $ssh = $testapi::distri->add_console(
        'remote-ssh',
        'ssh-xterm',
        {
            hostname => $bmwqemu::vars{HYPERVISOR_HOSTNAME} or die 'Undefined HYPERVISOR_HOSTNAME',
            password => $bmwqemu::vars{HYPERVISOR_PASSWORD} or die 'Undefined HYPERVISOR_PASSWORD',
            username => $bmwqemu::vars{HYPERVISOR_USERNAME} // 'root',
            persistent => 1});
    $ssh->backend($self);

    return {};
}

sub do_stop_vm ($self, @) {
    $self->stop_serial_grab;
    $self->deactivate_console({testapi_console => 'remote-ssh'});
    return {};
}

sub run_cmd ($self, $cmd, $hostname = $bmwqemu::vars{HYPERVISOR_HOSTNAME}, $password = $bmwqemu::vars{HYPERVISOR_PASSWORD}) {
    my $username = $bmwqemu::vars{HYPERVISOR_USERNAME} // 'root';

    return $self->run_ssh_cmd($cmd, username => $username, password => $password, hostname => $hostname, keep_open => 0);
}

sub can_handle ($self, @) { }

sub is_shutdown ($self, @) { die 'Not implemented'; }

sub check_socket ($self, $fh, $write = undef) {
    return 1 if $self->check_ssh_serial($fh);
    return $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab ($self, @) { $self->stop_ssh_serial }

1;
