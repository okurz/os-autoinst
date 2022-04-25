# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Main;
use Mojo::Base -base, -signatures;
use Exporter 'import';

our @EXPORT_OK = qw(_get_version_string stop_commands stop_autotest stop_backend);


sub _get_version_string () {
    my $dirname = curfile->dirname;
    my $thisversion = qx{git -C $dirname rev-parse HEAD};
    chomp $thisversion;
    die 'Could not parse version' unless $thisversion;
    return "Current version is $thisversion [interface v$OpenQA::Isotovideo::Interface::version]";
}

# note: The subsequently defined stop_* functions are used to tear down the process tree.
#       However, the worker also ensures that all processes are being terminated (and
#       eventually killed).

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

1;
