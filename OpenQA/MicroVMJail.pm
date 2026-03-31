# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::MicroVMJail;
use Mojo::Base -base, -signatures;
use Mojo::File qw(path);
use Mojo::Util 'scope_guard';
use Mojo::JSON qw(encode_json);
use bmwqemu;
use log qw(diag fctwarn);

has [qw(socket kernel rootfs binary id)];
has [qw(pid)];

sub new ($class, %args) {
    my $self = $class->SUPER::new(\%args);
    $self->id($args{id} // "jail_$$");
    $self->socket('/tmp/firecracker_' . $self->id . '.socket');
    $self->binary($bmwqemu::vars{BACKEND_FIRECRACKER_BIN} // 'firecracker');
    $self->kernel($bmwqemu::vars{BACKEND_FIRECRACKER_KERNEL} || die 'Need BACKEND_FIRECRACKER_KERNEL');
    $self->rootfs($bmwqemu::vars{BACKEND_FIRECRACKER_ROOTFS} || die 'Need BACKEND_FIRECRACKER_ROOTFS');
    $self->{tap} = $bmwqemu::vars{BACKEND_FIRECRACKER_TAP};
    return $self;
}

sub start ($self, $init_cmd) {
    unlink($self->socket);

    my $pid = fork();
    if ($pid == 0) {
        # Child: run firecracker
        exec($self->binary, '--api-sock', $self->socket);
        die 'exec firecracker failed: ' . $!;
    }
    $self->pid($pid);

    # Wait for API socket
    my $retries = 10;
    while (!-S $self->socket && $retries-- > 0) {
        select(undef, undef, undef, 0.1);
    }
    die 'Firecracker API socket not found' unless -S $self->socket;

    # Configure VM
    $self->_api_put('/boot-source', {
            kernel_image_path => $self->kernel,
            boot_args => 'console=ttyS0 reboot=k panic=1 pci=off init=/bin/sh -- -c "' . $init_cmd . '"'
    });

    $self->_api_put('/drives/rootfs', {
            drive_id => 'rootfs',
            path_on_host => $self->rootfs,
            is_root_device => Mojo::JSON->true,
            is_read_only => Mojo::JSON->false
    });

    if ($self->{tap}) {
        $self->_api_put('/network-interfaces/eth0', {
                iface_id => 'eth0',
                host_dev_name => $self->{tap}
        });
    }

    $self->_api_put('/actions', {
            action_type => 'InstanceStart'
    });

    diag('MicroVM jail started (PID: ' . $pid . ')' . ($self->{tap} ? " with networking on $self->{tap}" : ''));
    return $self;
}

sub stop ($self) {
    return unless $self->pid;
    kill('TERM', $self->pid);
    waitpid($self->pid, 0);
    unlink($self->socket);
    $self->pid(undef);
}

sub _api_put ($self, $path, $data) {
    my $json = encode_json($data);
    my $socket = $self->socket;
    my $cmd = "curl -s -X PUT --unix-socket $socket http://localhost$path " .
      "-H 'Accept: application/json' -H 'Content-Type: application/json' -d '$json'";
    my $output = qx($cmd);
    if ($? != 0) {
        fctwarn "Firecracker API PUT $path failed: $output";
    }
}

1;
