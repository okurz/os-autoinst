# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package common;

use Mojo::Base -strict, -signatures;;
use Exporter 'import';
our @EXPORT_OK = qw(RESULT_DIR);

use constant RESULT_DIR => 'testresults';

1;
