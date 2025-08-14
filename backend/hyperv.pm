# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::hyperv;
use Mojo::Base 'backend::svirt', -signatures;


sub is_shutdown ($self, @) {
    my $vmname = $self->console('svirt')->name;
    return $self->run_ssh_cmd("powershell -Command \"if (\$(Get-VM -VMName $vmname \| Where-Object {\$_.state -eq 'Off'})) { exit 1 } else { exit 0 }\"");
}

sub do_stop_vm_impl ($self, $vmname) {
    my $ps = 'powershell -Command';
    $self->run_ssh_cmd("$ps Stop-VM -Force -VMName $vmname -TurnOff");
    $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Remove-VM -Force -VMName $vmname"));
    return undef;
}

sub save_snapshot_impl ($self, $args) {
    my $vmname = $self->vmname();
    my $snapname = $args->{name};
    my $ps = 'powershell -Command';
    $self->run_ssh_cmd("$ps Remove-VMSnapshot -VMName $vmname -Name $snapname");
    $rsp = $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Checkpoint-VM -VMName $vmname -SnapshotName $snapname"));
}

sub load_snapshot_impl ($self, $args) {
    my $snapname = $args->{name};
    my $vmname = $self->vmname();
    my $ps = 'powershell -Command';
    $rsp = $self->run_ssh_cmd(qq($ps "\$ProgressPreference='SilentlyContinue'; Restore-VMSnapshot -VMName $vmname -Name $snapname -Confirm:\$false"));
    $self->run_ssh_cmd("mv -v xfreerdp_${vmname}_stop xfreerdp_${vmname}_stop.bkp", $self->get_ssh_credentials('hyperv'));

    for my $i (1 .. 5) {
        # Because of FreeRDP issue https://github.com/FreeRDP/FreeRDP/issues/3876,
        # we can't connect too "early". Let's have a nap for a while.
        sleep 10;
        last
          unless $self->run_ssh_cmd(
            "pgrep --full --list-full xfreerdp.*\$(cat xfreerdp_${vmname}_stop.bkp)",
            $self->get_ssh_credentials('hyperv'));
        $self->die("xfreerdp did not start") if ($i eq 5);
    }
}

1;
