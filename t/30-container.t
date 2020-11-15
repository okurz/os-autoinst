#!/usr/bin/perl
# Copyright (C) 2018-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Test::More;
use Test::Warnings ':report_warnings';
use OpenQA::Test::TimeLimit '40';
use Mojo::File qw(tempdir);
use FindBin '$Bin';
use Mojo::Util qw(scope_guard);

my $dir          = tempdir;
my $toplevel_dir = "$Bin/..";
my $data_dir     = "$Bin/data";
my $pool_dir     = "$dir/pool";
mkdir $pool_dir;
chdir $pool_dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $out = qx{podman build -f $toplevel_dir/docker/isotovideo/Dockerfile.qemu . 2>&1};
my $rc  = $? >> 8;
is $rc,      0,            'container could be built successfully' or diag "Output: $out";
unlike $out, qr/[eE]rror/, 'no errors building container' if $out;
done_testing;
