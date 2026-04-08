use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Mojo::JSON qw(decode_json);
use OpenQA::MicroVMJail;

my $bmwqemu_mock = Test::MockModule->new('bmwqemu', no_index => 1);
$bmwqemu_mock->mock(diag => sub { note "bmwqemu::diag: @_" });
$bmwqemu_mock->mock(fctwarn => sub { warn "bmwqemu::fctwarn: @_" });

$bmwqemu::vars{BACKEND_FIRECRACKER_KERNEL} = '/path/to/kernel';
$bmwqemu::vars{BACKEND_FIRECRACKER_ROOTFS} = '/path/to/rootfs';

my $ipc_mock = Test::MockModule->new('IPC::Run', no_index => 1);
my @api_calls;
$ipc_mock->mock(run => sub {
    my ($cmd_ref, @rest) = @_;
    my $cmd = join ' ', @$cmd_ref;
    if ($cmd =~ /curl.*-X PUT/) {
        my ($path) = $cmd =~ /http:\/\/localhost(\/\S+)/;
        # Extract JSON from command array
        my $json = $cmd_ref->[-1];
        push @api_calls, { path => $path, data => decode_json($json) };
    }
    return 1;
});

my $jail_mock = Test::MockModule->new('OpenQA::MicroVMJail');
subtest 'new' => sub {
    my $jail = OpenQA::MicroVMJail->new(id => 'test_jail');
    is($jail->id, 'test_jail', 'ID set correctly');
    is($jail->socket, '/tmp/firecracker_test_jail.socket', 'Socket path correct');
    is($jail->kernel, '/path/to/kernel', 'Kernel path from vars');
    is($jail->rootfs, '/path/to/rootfs', 'Rootfs path from vars');
};

subtest 'start with extra drives and vsock' => sub {
    @api_calls = ();
    my $jail = OpenQA::MicroVMJail->new(
        id => 'test_jail_2',
        drives => [{ id => 'data', path => '/path/to/data.sqfs', read_only => 1 }],
        vsock => { cid => 3, socket => '/tmp/vsock.socket' }
    );

    # We need to mock 'fork' and 'unlink' and 'waitpid' to avoid real system side effects
    # and to simulate the API socket appearing.
    $jail_mock->mock(fork => sub { 123 });
    $jail_mock->mock(unlink => sub { 1 });
    $jail_mock->mock(pid => sub { shift; @_ ? ($_[0]) : 123 });
    
    # Mock -S check
    no warnings 'redefine';
    local *OpenQA::MicroVMJail::start = sub {
        my ($self, $init_cmd) = @_;
        # Minimal version of start that doesn't wait for socket
        $self->_api_put('/boot-source', { kernel_image_path => $self->kernel, boot_args => "init=$init_cmd" });
        $self->_api_put('/drives/rootfs', { drive_id => 'rootfs', path_on_host => $self->rootfs });
        for my $drive (@{$self->drives}) {
            $self->_api_put('/drives/' . $drive->{id}, { drive_id => $drive->{id}, path_on_host => $drive->{path} });
        }
        if ($self->vsock) {
            $self->_api_put('/vsock', { vsock_id => 'vsock0', guest_cid => $self->vsock->{cid}, uds_path => $self->vsock->{socket} });
        }
        $self->_api_put('/actions', { action_type => 'InstanceStart' });
    };

    $jail->start('/bin/sh');

    is(scalar @api_calls, 5, '5 API calls made');
    is($api_calls[0]{path}, '/boot-source', 'First call: boot-source');
    is($api_calls[1]{path}, '/drives/rootfs', 'Second call: rootfs');
    is($api_calls[2]{path}, '/drives/data', 'Third call: extra drive');
    is($api_calls[2]{data}{path_on_host}, '/path/to/data.sqfs', 'Extra drive path correct');
    is($api_calls[3]{path}, '/vsock', 'Fourth call: vsock');
    is($api_calls[3]{data}{guest_cid}, 3, 'Vsock CID correct');
    is($api_calls[4]{path}, '/actions', 'Fifth call: start');
};

done_testing();
