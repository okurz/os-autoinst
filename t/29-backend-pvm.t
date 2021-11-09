#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use distribution;
use backend::pvm;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $mock = Test::MockModule->new('backend::pvm');
$mock->redefine(_masterlpar => '42');
$ENV{PVMCTL} = '/bin/true';
my $backend;
stderr_like { $backend = backend::pvm->new } qr/DEPRECATED/, 'backend marked as deprecated';
my $distri = $testapi::distri = distribution->new;
$bmwqemu::vars{WORKER_ID} = 1;
$bmwqemu::vars{ISO} = 'foo.iso';
$bmwqemu::vars{ARCH} = 'ppc64';
is_deeply $backend->do_start_vm, {}, 'can call do_start_vm';
is_deeply $backend->do_stop_vm, {}, 'can call do_stop_vm';
is $backend->do_start_vm, 1, 'can call do_start_vm';
is $backend->do_extract_assets, 1, 'can call extract_assets';
is $backend->pvmctl, 1, 'can call pvmctl';
is $backend->attach_console, 1, 'can call attach_console';
is $backend->image_exists, 1, 'can call image_exists';
is $backend->start_lpar, 1, 'can call start_lpar';
is $backend->_status, 1, 'can call _status';
is $backend->is_shutdown, 1, 'can call is_shutdown';
is $backend->do_stop_vm, 1, 'can call do_stop_vm';

my $baseclass = Test::MockModule->new('backend::baseclass');
$baseclass->redefine(run_ssh_cmd => undef);
is $backend->run_cmd('foo'), undef, 'can call run_cmd';
is $backend->can_handle, undef, 'can call can_handle';
$bmwqemu::vars{NOVALINK_LPAR_ID} = 1;
is $backend->is_shutdown, undef, 'can call is_shutdown';
is $backend->stop_serial_grab, undef, 'can call stop_serial_grab';
is $backend->check_socket(undef), 0, 'can call check_socket';
is $backend->power({action => 'off'}), undef, 'can call power';

done_testing;
