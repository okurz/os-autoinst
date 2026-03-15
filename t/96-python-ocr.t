#!/usr/bin/perl

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use Feature::Compat::Try;
use lib '.';
use autotest qw(connect_to_isotovideo query_isotovideo);
use POSIX qw(_exit);
use tinycv;
use ocr;

# Start Python isotovideo in background
my $socket_path = "/tmp/os-autoinst-python-ocr-$$.sock";
$ENV{OS_AUTOINST_PYTHON_SOCKET} = $socket_path;
$ENV{OS_AUTOINST_RUST_CORE} = 1;

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
    kill 'TERM', $pid;
    plan skip_all => "Python isotovideo server failed to start at $socket_path";
}

try {
    connect_to_isotovideo($socket_path);

    my $img = tinycv::read('t/data/welcome.ref.png');
    die "Could not read t/data/welcome.ref.png" unless $img;

    # This should call into python bridge
    my $text = ocr::tesseract($img, undef);
    ok length($text) > 0, 'OCR returned some text';
    like $text, qr/Welcome/i, 'OCR text contains "Welcome"';

    # Send quit command to server
    query_isotovideo('quit');
}
catch ($e) {
    fail "Integration test failed: $e";
}
finally {
    kill 'TERM', $pid;
    waitpid($pid, 0);
    unlink $socket_path if -S $socket_path;
}

done_testing;
