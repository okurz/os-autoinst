# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Main;
use Mojo::Base -base, -signatures;
use Exporter 'import';
use Time::HiRes qw(gettimeofday tv_interval sleep time);
use autotest ();
use log qw(diag fctwarn);

our @EXPORT_OK = qw(start_command_server start_autotest_process
  stop_commands stop_autotest stop_backend
  signalhandler init_backend
  check_asserted_screen main_loop handle_shutdown
  launch_debugging_tools handle_child_processes);

my $backend_process;
my $cmd_srv_fd;
my $cmd_srv_port;
my $cmd_srv_process;
my $command_handler;
my $loop = 1;
my $return_code;
my $testprocess;


# note: The subsequently defined stop_* functions are used to tear down the process tree.
#       However, the worker also ensures that all processes are being terminated (and
#       eventually killed).

sub start_command_server () {
    # start the command fork before we get into the backend, the command child
    # is not supposed to talk to the backend directly
    ($cmd_srv_process, $cmd_srv_fd) = commands::start_server($cmd_srv_port = $bmwqemu::vars{QEMUPORT} + 1);
}

sub start_autotest_process () {
    my $testfd;
    ($testprocess, $testfd) = autotest::start_process();
    return $testfd;
}

sub stop_commands ($reason) {
    return unless defined $cmd_srv_process;
    return unless $cmd_srv_process->is_running;

    my $pid = $cmd_srv_process->pid;
    diag("stopping command server $pid because $reason");

    if ($cmd_srv_port && $reason && $reason eq 'test execution ended') {
        my $job_token = $bmwqemu::vars{JOBTOKEN};
        my $url = "http://127.0.0.1:$cmd_srv_port/$job_token/broadcast";
        diag('isotovideo: informing websocket clients before stopping command server: ' . $url);

        # note: If the job is stopped by the worker because it has been
        # aborted, the worker will send this command on its own to the command
        # server and also stop the command server. So this is only done in the
        # case the test execution just ends.

        my $timeout = 15;
        # The command server might have already been stopped by the worker
        # after the user has aborted the job or the job timeout has been
        # exceeded so no checks for failure done.
        Mojo::UserAgent->new(request_timeout => $timeout)->post($url, json => {stopping_test_execution => $reason});
    }

    $cmd_srv_process->stop();
    $cmd_srv_process = undef;
    diag('done with command server');
}

sub stop_autotest () {
    return unless defined $testprocess;

    diag('stopping autotest process ' . $testprocess->pid);
    $testprocess->stop() if $testprocess->is_running;
    $testprocess = undef;
    diag('done with autotest process');
}

sub stop_backend () {
    return unless defined $bmwqemu::backend && $backend_process;

    diag('stopping backend process ' . $backend_process->pid);
    $backend_process->stop if $backend_process->is_running;
    $backend_process = undef;
    diag('done with backend process');
}

sub signalhandler ($sig) {
    bmwqemu::serialize_state(component => 'isotovideo', msg => "isotovideo received signal $sig", log => 1);
    return $loop = 0 if $loop;
    stop_backend;
    stop_commands("received signal $sig");
    stop_autotest;
    _exit(1);
}

sub init_backend () {
    $bmwqemu::vars{BACKEND} ||= "qemu";
    $bmwqemu::backend = backend::driver->new($bmwqemu::vars{BACKEND});
    return $bmwqemu::backend;
}

sub _calc_check_delta ($last_check_seconds, $last_check_microseconds) {
    # an estimate of eternity
    my $delta = $last_check_seconds ? tv_interval([$last_check_seconds, $last_check_microseconds], [gettimeofday]) : 100;
    # sleep the remains of one second if $delta > 0
    my $timeout = $delta > 0 ? 1 - $delta : 0;
    $command_handler->timeout($timeout < 0 ? 0 : $timeout);
    return $delta;
}

sub check_asserted_screen ($last_check_seconds, $last_check_microseconds, $testfd, $no_wait = undef) {
    if ($no_wait) {
        # prevent CPU overload by waiting at least a little bit
        $command_handler->timeout(0.1);
    }
    else {
        _calc_check_delta($last_check_seconds, $last_check_microseconds);
        # come back later, avoid too often called function
        return if $command_handler->timeout > 0.05;
    }
    ($last_check_seconds, $last_check_microseconds) = gettimeofday;
    my $rsp = $bmwqemu::backend->_send_json({cmd => 'check_asserted_screen'}) || {};
    # the test needs that information
    $rsp->{tags} = $command_handler->tags;
    if ($rsp->{found} || $rsp->{timeout}) {
        myjsonrpc::send_json($testfd, {ret => $rsp});
        $command_handler->clear_tags_and_timeout();
    }
    else {
        _calc_check_delta($last_check_seconds, $last_check_microseconds) unless $no_wait;
    }
}

sub main_loop ($testfd, $io_select) {
    my ($last_check_seconds, $last_check_microseconds) = gettimeofday;
    # enter the main loop: process messages from autotest, command server and backend
    while ($loop) {
        # FIXME undefined value $command_handler
        my ($ready_for_read, $ready_for_write, $exceptions) = IO::Select::select($io_select, undef, $io_select, $command_handler->timeout);
        for my $readable (@$ready_for_read) {
            my $rsp = myjsonrpc::read_json($readable);
            if (!defined $rsp) {
                fctwarn sprintf("THERE IS NOTHING TO READ %d %d %d", fileno($readable), fileno($testfd), fileno($cmd_srv_fd));
                $readable = 1;
                $loop = 0;
                last;
            }
            if ($readable == $backend_process->channel_out) {
                $command_handler->send_to_backend_requester({ret => $rsp->{rsp}});
                next;
            }
            $command_handler->process_command($readable, $rsp);
        }
        check_asserted_screen($last_check_seconds, $last_check_microseconds, $testfd, $command_handler->no_wait) if defined $command_handler->tags;
    }
}

sub handle_shutdown ($testfd) {
    # tell the command server that it should no longer process isotovideo commands since we've
    # just left the loop which would handle such commands (otherwise the command server would just
    # hang on the next isotovideo command)
    $command_handler->stop_command_processing;

    # terminate/kill the command server and let it inform its websocket clients before
    stop_commands('test execution ended');

    $return_code = 0;
    if ($testfd) {
        $return_code = 1;    # unusual shutdown
        CORE::close $testfd;
        stop_autotest;
    }

    diag 'isotovideo ' . ($return_code ? 'failed' : 'done');

    my $clean_shutdown;
    if (!$return_code) {
        eval {
            $clean_shutdown = $bmwqemu::backend->_send_json({cmd => 'is_shutdown'});
            diag('backend shutdown state: ' . ($clean_shutdown // '?'));
        };

        # don't rely on the backend in a sane state if we failed - just stop it later
        eval { bmwqemu::stop_vm() };
        if ($@) {
            bmwqemu::serialize_state(component => 'backend', msg => "unable to stop VM: $@", error => 1);
            $return_code = 1;
        }
    }

    # read calculated variables from backend and tests
    bmwqemu::load_vars();

    $return_code = handle_generated_assets($command_handler, $clean_shutdown) unless $return_code;
}

sub launch_debugging_tools () {
    my %debugging_tools;
    $debugging_tools{vncviewer} = ['vncviewer', '-viewonly', '-shared', "localhost:$bmwqemu::vars{VNC}"] if $ENV{RUN_VNCVIEWER};
    $debugging_tools{debugviewer} = ["$bmwqemu::scriptdir/debugviewer/debugviewer", 'qemuscreenshot/last.png'] if $ENV{RUN_DEBUGVIEWER};
    for my $tool (keys %debugging_tools) {
        next if fork() != 0;  # uncoverable statement
        no autodie 'exec';  # uncoverable statement
        { exec(@{$debugging_tools{$tool}}) };  # uncoverable statement
        # don't continue in any case (exec returns if it fails to spawn the process printing an error message on its own)
        # uncoverable statement
        exit -1;
    }
}

sub handle_child_processes () {
    # stop main loop as soon as one of the child processes terminates
    my $stop_loop = sub (@) { $loop = 0 if $loop; };
    $testprocess->once(collected => $stop_loop);
    return unless $backend_process;
    $backend_process->once(collected => $stop_loop);
    return unless $cmd_srv_process;
    $cmd_srv_process->once(collected => $stop_loop);
}

1;
