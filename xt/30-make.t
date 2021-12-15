#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Test::Output 'stderr_like';
use Mojo::File qw(path tempdir);
use Mojo::Util 'scope_guard';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '20';

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $srcdir = path("$Bin/..")->realpath;
stderr_like { is qx{git -C $dir clone $srcdir}, '', 'prepare working copy with git' } qr/Cloning/, 'git clone';
chdir "$dir/os-autoinst";
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
is $?, 0, 'prepare working copy with git (exit code)';
like qx{make}, qr/Symlinking created executables into source directory/, 'build default';
is $?, 0, 'build default (exit code)';
like qx{rm -rf build && make help}, qr/help: HELP/, 'call specific make target initially';
chdir '..';
like qx{rm -rf os-autoinst/build && make -C os-autoinst help}, qr/help: HELP/, 'call make with target initially from outside';
like qx{make -C os-autoinst help}, qr/help: HELP/, 'call make again with target from outside';
like qx{make -C os-autoinst}, qr/Symlinking created executables/, 'call make from outside without arguments';
done_testing;
