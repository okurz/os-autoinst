# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package common;

use strictures;
use Exporter 'import';
our @EXPORT_OK = qw(result_dir);

our %vars;
tie %vars, 'common::tiedvars', %vars;

sub result_dir () { 'testresults' }

1;
