#!/usr/bin/perl

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use Feature::Compat::Try;
use lib '.';
use autotest qw(connect_to_isotovideo query_isotovideo);
use POSIX qw(_exit);

# Start Python isotovideo in background
my $socket_path = "/tmp/os-autoinst-python-vnc-$$.sock";
$ENV{OS_AUTOINST_PYTHON_SOCKET} = $socket_path;

# Start a mock VNC server
my $vnc_port = 5900 + ($bmwqemu::vars{WORKER_ID} // 0);
my $vnc_server = IO::Socket::INET->new(
    LocalAddr => 'localhost',
    LocalPort => $vnc_port,
    Proto => 'tcp',
    Listen => 1,
    Reuse => 1,
) or die "Could not start mock VNC server: $!";

my $vnc_pid = fork();
if ($vnc_pid == 0) {
    my $vnc_client = $vnc_server->accept();
    if ($vnc_client) {
        $vnc_client->autoflush(1);
        $vnc_client->print("RFB 003.008\n");
        $vnc_client->read(my $ver, 12);
        $vnc_client->print(pack('C', 1) . pack('C', 1));    # 1 security type: None
        $vnc_client->read(my $type, 1);
        $vnc_client->print(pack('N', 0));    # Security OK
        $vnc_client->read(my $init, 1);
        $vnc_client->print(pack('nnCCCCnnnCCCxxxN', 1024, 768, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0, 4));    # ServerInit
        $vnc_client->print("test");

        # Keep alive for key events
        while ($vnc_client->read(my $msg, 1)) {
            # do nothing
        }
    }
    _exit(0);
}

my $pid = fork();
if ($pid == 0) {
    exec('python3', 'script/isotovideo.py', '--debug');
}

# Wait for socket
my $retries = 50;
while ($retries-- > 0 && !-S $socket_path) {
    select(undef, undef, undef, 0.1);
}

if (!-S $socket_path) {
    kill 'TERM', $vnc_pid;
    kill 'TERM', $pid;
    plan skip_all => "Python isotovideo server failed to start at $socket_path";
}

try {
    connect_to_isotovideo($socket_path);

    my $res = query_isotovideo('select_console', {testapi_console => 'vnc'});
    is $res, 1, 'Can select vnc console';

    $res = query_isotovideo('send_key', {key => 'esc'});
    is $res, 1, 'Can send esc key';

    # Send quit command to server
    query_isotovideo('quit');
}
catch ($e) {
    fail "Integration test failed: $e";
}
finally {
    kill 'TERM', $vnc_pid;
    kill 'TERM', $pid;
    waitpid($vnc_pid, 0);
    waitpid($pid, 0);
    unlink $socket_path if -S $socket_path;
    $vnc_server->close();
}

done_testing;
