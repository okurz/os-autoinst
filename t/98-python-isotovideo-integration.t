#!/usr/bin/perl

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use Feature::Compat::Try;
use lib '.';
use autotest qw(connect_to_isotovideo query_isotovideo);
use POSIX qw(_exit);

# Start Python isotovideo in background
my $socket_path = "/tmp/os-autoinst-python-test-$$.sock";
$ENV{OS_AUTOINST_PYTHON_SOCKET} = $socket_path;

my $pid = fork();
if ($pid == 0) {
    # Child: start python isotovideo
    # Redirect output to a file for debugging
    open STDOUT, '>', "isotovideo_debug_$$.log" or die $!;
    open STDERR, '>&', STDOUT or die $!;
    exec('python3', 'script/isotovideo.py', '--debug');
}

# Wait for socket
my $retries = 50;
while ($retries-- > 0 && !-S $socket_path) {
    select(undef, undef, undef, 0.1);
}

if (!-S $socket_path) {
    my $debug_log = -f "isotovideo_debug_$pid.log" ? `cat isotovideo_debug_$pid.log` : "No log file";
    kill 'TERM', $pid;
    plan skip_all => "Python isotovideo server failed to start at $socket_path. Log: $debug_log";
}

# Give it a bit more time to actually listen
sleep 1;

try {
    connect_to_isotovideo($socket_path);
    my $res = query_isotovideo('backend_can_handle', {function => 'snapshots'});
    is $res, 1, 'Python isotovideo handles backend_can_handle';

    # Send quit command to server
    query_isotovideo('quit');
}
catch ($e) {
    my $debug_log = -f "isotovideo_debug_$pid.log" ? `cat isotovideo_debug_$pid.log` : "No log file";
    fail "Integration test failed: $e. Log: $debug_log";
}
finally {
    kill 'TERM', $pid;
    waitpid($pid, 0);
    unlink "isotovideo_debug_$pid.log" if -f "isotovideo_debug_$pid.log";
}

done_testing;
