#!/usr/bin/perl
# Copyright 2019 SUSE LLC

BEGIN {
    *CORE::GLOBAL::syswrite => sub { 1 };
    *CORE::syswrite => sub { 1 };
}

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use Test::Fatal;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
#use Test::MockModule;
use consoles::serial_screen;

my $screen = consoles::serial_screen->new('read', 'write');
is($screen->{fd_write}, 'write', 'Check if channel was set for write fd');
is($screen->{fd_read}, 'read', 'Check if channel was set for read fd');
is($screen->{carry_buffer}, '', 'Check if channel was set for read fd');

$screen = consoles::serial_screen->new('same', 'same');
is($screen->{fd_read}, 'same', 'Fd read member was set.');
is($screen->{fd_read}, $screen->{fd_write}, 'If only one fd give, read and write are equal');

dies_ok { $screen->hold_key } 'hold_key dies with error';
dies_ok { $screen->release_key } 'release_key dies with error';
dies_ok { $screen->send_key({key => 'space'}) } 'send_key dies for most keys';
is $screen->current_screen, 0, 'no current screen';
is $screen->request_screen_update, undef, 'can call request_screen_update';

ok $screen->send_key({key => 'ret'}), 'can call send_key';

use subs qw(syswrite);
sub syswrite { 1 }
ok $screen->type_string({text => 'foo'}), 'can call type_string';
ok $screen->elapsed, 'can call elapsed';
ok $screen->remaining, 'can call remaining';
ok $screen->normalise_pattern, 'can call normalise_pattern';
ok $screen->do_read, 'can call do_read';
ok $screen->read_until, 'can call read_until';
ok $screen->peak, 'can call peak';
ok $screen->current_screen, 'can call current_screen';

done_testing;
