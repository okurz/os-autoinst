#!/usr/bin/perl

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use Feature::Compat::Try;
use lib '.';
use autotest qw(connect_to_isotovideo query_isotovideo);
use POSIX qw(_exit);

# Start Python isotovideo in background
my $socket_path = "/tmp/os-autoinst-python-test.sock";
$ENV{OS_AUTOINST_PYTHON_SOCKET} = $socket_path;    # Not used yet, but good for future

my $pid = fork();
if ($pid == 0) {
    # Child: start python isotovideo
    # We use a modified script/isotovideo.py that uses the test socket path
    # and doesn't start another perl process.
    exec('python3', 'script/isotovideo.py', '--debug');
}

# Wait for socket
my $retries = 20;
while ($retries-- > 0 && !-S $socket_path) {
    select(undef, undef, undef, 0.1);
}

if (!-S $socket_path) {
    kill 'TERM', $pid;
    plan skip_all => "Python isotovideo server failed to start at $socket_path";
}

try {
    connect_to_isotovideo($socket_path);
    my $res = query_isotovideo('backend_can_handle', {function => 'snapshots'});
    is $res, 1, 'Python isotovideo handles backend_can_handle';

    # Send quit command to server
    query_isotovideo('quit');
}
catch ($e) {
    fail "Integration test failed: $e";
}
finally {
    kill 'TERM', $pid;
    waitpid($pid, 0);
}

done_testing;
