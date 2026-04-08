# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::MicroVMJail;
use Mojo::Base -base, -signatures;
use Mojo::File qw(path);
use Mojo::Util 'scope_guard';
use Mojo::JSON qw(encode_json);
use IPC::Run;
use bmwqemu;
use log qw(diag fctwarn);

has [qw(socket kernel rootfs initrd binary id drives vsock)];
has [qw(pid)];

sub new ($class, %args) {
    my $self = $class->SUPER::new(\%args);
    $self->id($args{id} // "jail_$$");
    $self->socket('/tmp/firecracker_' . $self->id . '.socket');
    $self->binary($bmwqemu::vars{BACKEND_FIRECRACKER_BIN} // 'firecracker');
    $self->kernel($bmwqemu::vars{BACKEND_FIRECRACKER_KERNEL} || die 'Need BACKEND_FIRECRACKER_KERNEL');
    $self->rootfs($bmwqemu::vars{BACKEND_FIRECRACKER_ROOTFS} || die 'Need BACKEND_FIRECRACKER_ROOTFS');
    $self->initrd($bmwqemu::vars{BACKEND_FIRECRACKER_INITRD});
    $self->drives($args{drives} // []);
    $self->vsock($args{vsock});
    $self->{tap} = $bmwqemu::vars{BACKEND_FIRECRACKER_TAP};
    return $self;
}

sub start ($self, $init_cmd) {
    unlink $self->socket;

    my $pid = fork;
    if ($pid == 0) {
        # Child: run firecracker
        my $log = "/tmp/firecracker_" . $self->id . ".log";
        open STDOUT, '>', $log or die "Can't redirect STDOUT to $log: $!";
        open STDERR, '>&STDOUT' or die "Can't redirect STDERR: $!";
        exec $self->binary, '--api-sock', $self->socket;
        die 'exec firecracker failed: ' . $!;
    }
    $self->pid($pid);

    # Wait for API socket
    my $retries = 10;
    while (!-S $self->socket && $retries-- > 0) {
        select undef, undef, undef, 0.1;
    }
    die 'Firecracker API socket not found' unless -S $self->socket;

    # Configure VM
    my $boot_args = $bmwqemu::vars{BACKEND_FIRECRACKER_BOOTARGS} // 'console=ttyS0 reboot=k panic=1 pci=off';
    $boot_args .= ' init=/bin/sh -- -c "mkdir -p /mnt/os-autoinst && mount -v -o ro -t squashfs /dev/vdb /mnt/os-autoinst || ls -l /dev/vd*; /mnt/os-autoinst/bin/autotest-jail-init; reboot -f"';

    my $boot_config = {
        kernel_image_path => $self->kernel,
        boot_args => $boot_args
    };
    $boot_config->{initrd_path} = $self->initrd if $self->initrd;

    $self->_api_put('/boot-source', $boot_config);

    $self->_api_put('/drives/rootfs', {
            drive_id => 'rootfs',
            path_on_host => $self->rootfs,
            is_root_device => Mojo::JSON->true,
            is_read_only => Mojo::JSON->false
    });

    for my $drive (@{$self->drives}) {
        $self->_api_put('/drives/' . $drive->{id}, {
                drive_id => $drive->{id},
                path_on_host => $drive->{path},
                is_root_device => Mojo::JSON->false,
                is_read_only => $drive->{read_only} // Mojo::JSON->true
        });
    }

    if ($self->vsock) {
        $self->_api_put('/vsock', {
                guest_cid => $self->vsock->{cid},
                uds_path => $self->vsock->{socket}
        });
    }

    if ($self->{tap}) {
        $self->_api_put('/network-interfaces/eth0', {
                iface_id => 'eth0',
                host_dev_name => $self->{tap}
        });
    }

    $self->_api_put('/machine-config', {
            vcpu_count => 1,
            mem_size_mib => 512
    });

    $self->_api_put('/actions', {
            action_type => 'InstanceStart'
    });

    diag('MicroVM jail started (PID: ' . $pid . ')' . ($self->{tap} ? " with networking on $self->{tap}" : ''));
    return $self;
}

sub stop ($self) {
    return unless $self->pid;
    kill 'TERM', $self->pid;
    waitpid $self->pid, 0;
    unlink $self->socket;
    $self->pid(undef);
}

sub _api_put ($self, $path, $data) {
    my $json = encode_json($data);
    my $socket = $self->socket;
    my @cmd = ('curl', '-s', '-X', 'PUT', '--unix-socket', $socket, "http://localhost$path",
      '-H', 'Accept: application/json', '-H', 'Content-Type: application/json', '-d', $json);
    my ($stdout, $stderr);
    my $ret = IPC::Run::run(\@cmd, '>', \$stdout, '2>', \$stderr);
    if (!$ret) {
        fctwarn "Firecracker API PUT $path failed: $stderr";
    }
}

sub create_data_squashfs ($self, $path, @dirs) {
    my @cmd = ('mksquashfs', @dirs, $path, '-noappend', '-all-root');
    diag("Building Squashfs data image: " . join ' ', @cmd);
    system(@cmd) == 0 or die "mksquashfs failed: $!";
    return $path;
}

1;
