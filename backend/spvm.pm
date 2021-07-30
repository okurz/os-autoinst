# Copyright 2018-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::spvm;
use Mojo::Base 'backend::remote', -signatures;
use bmwqemu ();
use IO::Select;

# supporting the minimal command set of NovaLink through a ssh tunnel

sub is_shutdown ($self, @) {
    my $lpar_id = $bmwqemu::vars{NOVALINK_LPAR_ID} // die 'Need variable \'NOVALINK_LPAR_ID\'';
    return $self->run_cmd("! pvmctl  lpar list -i id=${lpar_id} | grep  'not a'");
}

sub check_socket ($self, $fh, $write = undef) { $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write) }

sub stop_serial_grab ($self, @) {
    $self->stop_ssh_serial;
    return;
}

# parameters: on, off, reset
sub power ($self, $args) {
    my $action = $args->{action};
    my $lpar_id = $bmwqemu::vars{NOVALINK_LPAR_ID} // die 'Need variable \'NOVALINK_LPAR_ID\'';

    my %cmds = (
        on => "pvmctl lpar power-on -i id=${lpar_id} --bootmode norm",
        off => "pvmctl lpar power-off -i id=${lpar_id} --hard",
        reset => "pvmctl lpar restart -i id=${lpar_id}");
    $self->run_cmd($cmds{$action}) if (exists $cmds{$action}) || die "Unknown power action ${action}";
}
1;
