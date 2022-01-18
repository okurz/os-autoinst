# Copyright 2016 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::virt;

use Mojo::Base 'backend::baseclass', -signatures;
use bmwqemu;

sub new ($class) {
    my $self = $class->SUPER::new;
    $tiedvars::vars{QEMURAM} //= 1024;
    $tiedvars::vars{QEMUCPUS} //= 1;
    return $self;
}

1;
