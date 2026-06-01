#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Output qw(combined_like);
use Test::MockModule;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use distribution;
use OpenQA::Test::TimeLimit '5';

my @wait_serial_calls;

my $mock_bmwqemu_global = Test::MockModule->new('bmwqemu');
$mock_bmwqemu_global->noop('log_call');

subtest 'script_run' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    throws_ok { $d->script_run() } qr/^Too few arguments/, 'Error on incorrect usage';
    like warning { $d->script_run('foo') }, qr/^Use of uninitialized.*serialdev/, 'Warning on undefined serialdev';
    {
        no warnings 'once';
        $testapi::serialdev = 'my_serial';
    }
    my $typed_string = '';
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    lives_ok { $d->script_run('foo') } 'script_run succeeds with trivial command';
    like $typed_string, qr/foo; echo .* > .*serial/, 'command is typed plus marker and redirection';
    $typed_string = '';
    throws_ok { $d->script_run('foo &') } qr/Terminator.*found.*background_script_run/, 'script_run with terminator is caught';
    lives_ok { $d->script_run('foo\&') } 'escaped terminator is accepted';
    lives_ok { $d->script_run('foo && bar') } 'AND operator is accepted';
    lives_ok { $d->script_run('foo "x&"') } 'quoted & is accepted';
    my $wait_serial_res = 1;
    $mock_testapi->redefine(wait_serial => sub ($regexp, @args) {
            push @wait_serial_calls, {
                regexp => $regexp,
                timeout => 90,
                expect_not_found => 0,
                quiet => undef,
                no_regex => 0,
                buffer_size => undef,
                record_output => undef,
                @args
            };
            return $wait_serial_res;
    });
    $mock_testapi->redefine(is_serial_terminal => 1);
    $d->script_run('short_command');
    # script_run calls wait_serial three times when on a serial
    # console, the call we want to check - which actually types the
    # command - is the second
    my $cmdcall = $wait_serial_calls[1];
    is $cmdcall->{buffer_size}, 141, 'appropriate buffer size used for short command';
    @wait_serial_calls = ();
    $d->script_run('long_command' x 512);
    $cmdcall = $wait_serial_calls[1];
    is $cmdcall->{buffer_size}, 6272, 'appropriate buffer size used for long command';

    $wait_serial_res = 0;
    @wait_serial_calls = ();
    throws_ok { $d->script_run('foo') } qr/typing command 'foo' timed out/, 'timeout while typing command handled';

    @wait_serial_calls = ();
    combined_like { $d->script_run('foo', check_typing_cmd => 0) }
    qr/typing command 'foo' timed out/, 'timeout while typing command just logged when opted-out';
};

subtest 'pretty_serial_marker' => sub {
    my $d = distribution->new;
    my ($mock_testapi) = _setup_pretty_marker_mock();
    my $typed_string = '';
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    $mock_testapi->redefine(hashed_string => sub { return 'SR' . substr $_[0], 0, 8 });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });

    # Case: Bash 4.4 -> Level 3
    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'OA:DONE-0-SRfoo';
    });

    $typed_string = '';
    $d->script_run('foo');
    is $d->{_serial_marker_level}->{'test-console'}, 3, 'Level 3 detected for Bash 4.4';
    like $typed_string, qr/cat > \/tmp\/h <<'EOF'/, 'Level 3 installs hook';
    like $typed_string, qr/export OA_M=.*; foo\n/, 'Level 3 types OA_M marker';

    # Case: Bash 3.2 -> Level 2
    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:3.2:' if ref($regexp) eq 'Regexp' && 'BASH:3.2:' =~ $regexp;
            return 'SRfoo-0-';
    });

    $d->{_serial_marker_level} = {};
    $typed_string = '';
    $d->script_run('foo');
    is $d->{_serial_marker_level}->{'test-console'}, 2, 'Level 2 detected for Bash 3.2';
    like $typed_string, qr/export __OA_MARK=.*; foo\n/, 'Level 2 uses export marker';


    $mock_testapi->redefine(wait_serial => sub { undef });
    $d->{_serial_marker_level} = {};
    $typed_string = '';
    is $d->_detect_serial_marker_capability(), 1, 'Fallback to Level 1 if BASH detection fails';

    $d->{_serial_marker_level}->{'test-console'} = 3;
    $mock_testapi->redefine(wait_serial => sub { undef });
    is $d->script_run('foo'), undef, 'script_run returns undef if wait_serial fails (Level 2)';

    $d->{_serial_marker_level}->{'test-console'} = 1;
    $mock_testapi->redefine(wait_serial => sub { 'SRfoo-0-' });

    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $typed_string = '';
    $d->script_run('foo');
    like $typed_string, qr/foo; echo SR.*-.*- > \/dev\/ttyS0\n/, 'Level 1 uses classic marker with redirection';

    $mock_testapi->redefine(is_serial_terminal => sub { 1 });
    $typed_string = '';
    $d->script_run('foo');
    like $typed_string, qr/foo; echo SR.*-.*-\n/, 'Level 1 uses classic marker on serial terminal';

    $mock_testapi->redefine(wait_serial => sub ($pat, %args) {
            return 0 if $pat =~ /foo; echo SR.*-\$\?-/;
            return 'SRfoo-0-';
    });
    throws_ok { $d->script_run('foo') } qr/typing command 'foo' timed out/, 'typing error handled in Level 1';
};

sub _setup_pretty_marker_mock () {
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? 1 : undef });
    $testapi::serialdev = 'ttyS0';
    return ($mock_testapi, $mock_bmwqemu);
}

subtest 'pretty_serial_marker_concurrency' => sub {
    my $d = distribution->new;
    my ($mock_testapi, $mock_bmwqemu) = _setup_pretty_marker_mock();
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $mock_testapi->redefine(hashed_string => sub { return 'SRcurl' });
    # background 'tar' (exit 1) followed by foreground 'curl' (exit 0)
    $mock_testapi->redefine(wait_serial => sub { 'OA:DONE-1-SRtarOA:DONE-0-SRcurl' });
    is $d->script_run('curl http://localhost/url'), 0, 'Level 3 isolates target fingerprint from background markers';
};

subtest 'pretty_serial_marker_complex_cmds' => sub {
    my $d = distribution->new;
    my ($mock_testapi, $mock_bmwqemu) = _setup_pretty_marker_mock();
    $d->{_serial_marker_level}->{'test-console'} = 3;

    my @cases = (
        {cmd => "cat <<EOF\nfoo\nEOF", msg => 'multi-line here-doc'},
        {cmd => "echo 'hello'; >&2 echo \"world\"", msg => 'complex quoting'},
        {cmd => 'rm -rf /', msg => 'short command'},
        {cmd => 'abc', msg => 'very short command'}
    );

    for my $case (@cases) {
        $mock_testapi->redefine(hashed_string => sub { return 'SRhash' });
        $mock_testapi->redefine(wait_serial => sub { ref($_[0]) eq 'Regexp' && "OA:DONE-0-SRhash" =~ $_[0] ? "OA:DONE-0-SRhash" : undef });
        is $d->script_run($case->{cmd}), 0, "Level 3 handles $case->{msg}";
    }
};

subtest 'pretty_serial_marker_fragmented' => sub {
    my $d = distribution->new;
    my ($mock_testapi, $mock_bmwqemu) = _setup_pretty_marker_mock();
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $mock_testapi->redefine(hashed_string => sub { return 'SRhash' });
    $mock_testapi->redefine(wait_serial => sub { 'OA:DONE-0-WRONG' });
    is $d->script_run('zypper lr'), undef, 'Level 3 returns undef on missing fingerprint';
};

subtest 'pretty_serial_marker_redirection_guard' => sub {
    my $d = distribution->new;
    my $typed = '';
    my ($mock_testapi, $mock_bmwqemu) = _setup_pretty_marker_mock();
    $mock_bmwqemu->noop('diag');
    $mock_testapi->redefine(type_string => sub {
            my ($str, %args) = @_;
            # special argument handling for backward compat
            if (@_ == 2 && !ref $_[1]) {
                %args = (max_interval => $_[1]);
            }
            $typed .= $str;
            $typed .= "\n" if $args{lf};
    });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $mock_testapi->redefine(wait_serial => sub { $_[0] =~ /SRfoo/ ? 'SRfoo-0-' : undef });

    $d->script_run('echo test > /dev/ttyS0');
    like $typed, qr/OA_NO_MARKER=1; /, 'OA_NO_MARKER=1 prepended for manual redirection';
};

subtest 'pretty_serial_marker_multi_console' => sub {
    my $d = distribution->new;
    my $typed = '';
    my ($mock_testapi, $mock_bmwqemu) = _setup_pretty_marker_mock();
    $mock_testapi->redefine(type_string => sub {
            my ($str, %args) = @_;
            # special argument handling for backward compat
            if (@_ == 2 && !ref $_[1]) {
                %args = (max_interval => $_[1]);
            }
            $typed .= $str;
            $typed .= "\n" if $args{lf};
    });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(wait_serial => sub {
            return 'BASH:4.4:' if ref($_[0]) eq 'Regexp' && 'BASH:4.4:' =~ $_[0];
            return 'OA:DONE-0-SRfoo';
    });

    $mock_testapi->redefine(current_console => sub { 'console1' });
    $typed = '';
    $d->script_run('foo');
    like $typed, qr/cat > \/tmp\/h <<'EOF'/, 'install on console1';
    ok $d->{_serial_marker_hook_installed}->{console1}, 'console1 installed';

    $mock_testapi->redefine(current_console => sub { 'console2' });
    $typed = '';
    $d->script_run('foo');
    like $typed, qr/cat > \/tmp\/h <<'EOF'/, 'independent install on console2';
    ok $d->{_serial_marker_hook_installed}->{console2}, 'console2 installed';

    $mock_testapi->redefine(current_console => sub { 'console1' });
    $typed = '';
    $d->script_run('foo');
    unlike $typed, qr/cat > \/tmp\/h <<'EOF'/, 'no re-install on console1';
};

done_testing;

1;
