# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package myjsonrpc;

use Mojo::Base -strict, -signatures;
use Carp qw(cluck confess);
use IO::Select;
use Errno;
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();
use bmwqemu ();

use constant DEBUG_JSON => $ENV{PERL_MYJSONRPC_DEBUG} || 0;
use constant READ_BUFFER => $ENV{PERL_MYJSONRPC_BYTES} || 8_000_000;

# hash for keeping state
our $sockets;

sub is_debug () { DEBUG_JSON || $bmwqemu::vars{DEBUG_JSON_RPC} }

sub send_json ($to_fd, $cmd) {
    # allow regular expressions to be automatically converted into
    # strings, using the Regex::TO_JSON function as defined at the end
    # of this file.
    # The resulting JSON should be in a single line, otherwise
    # read_json won't work
    my $cjx = Cpanel::JSON::XS->new->canonical->utf8->convert_blessed();

    # deep copy to add a random string
    my %cmdcopy = %$cmd;
    # The hash might already contain a json_cmd_token
    $cmdcopy{json_cmd_token} ||= bmwqemu::random_string(8);

    my $json = $cjx->encode(\%cmdcopy);
    bmwqemu::diag(sprintf("send_json(%d) JSON=%s", fileno($to_fd), $json =~ s/"([^"]{30})[^"]+"/"$1"/gr)) if is_debug;
    $json .= "\n";

    confess 'myjsonprc: called on undefined file descriptor' unless defined $to_fd;
    my $wb = syswrite($to_fd, "$json");
    if (!$wb || $wb != length($json)) {
        die('myjsonrpc: remote end terminated connection, stopping') if !DEBUG_JSON && $! =~ qr/Broken pipe/;
        confess "syswrite failed: $!";
    }
    return $cmdcopy{json_cmd_token};
}

sub do_read_json ($cjx, $multi, $fd, $socket, $select, $cmd_token, $results) {
    my $hash = $cjx->incr_parse();
    # remember the trailing text
    warn("do_read_json");
    if ($hash) {
        warn("do_read_json: if hash true");
        $sockets->{$fd} = $cjx->incr_text();
        bmwqemu::diag("read_json($fd) json_cmd_token=" . $hash->{json_cmd_token} // 'no-token') if is_debug;
        if ($hash->{QUIT}) {
            bmwqemu::diag("received magic close");
            push @$results, undef;
            return 1;
        }
        confess "ERROR: the token does not match - questions and answers not in the right order" if $cmd_token && ($hash->{json_cmd_token} || '') ne $cmd_token; # uncoverable statement
        push @$results, $hash;
        # parse all lines from buffer
        next if $multi;
        return 1;
    }
    elsif ($multi and @$results) {
        warn("do_read_json: multi");
        # read at least one item in list context
        return 1;
    }

    # wait for next read
    until (my @res = $select->can_read) {
        warn("do_read_json: in until");
        # throw an error except can_read has been interrupted
        my $error = $!;
        confess "ERROR: unable to wait for JSON reply: $error\n" unless $!{EINTR};
        # try again if can_read's underlying system call has been interrupted as suggested by the perlipc documentation
        bmwqemu::diag("read_json($fd): can_read's underlying system call has been interrupted, trying again\n") if is_debug;
    }

    my $qbuffer;
    warn("do_read_json: before sysread");
    my $bytes = sysread($socket, $qbuffer, READ_BUFFER) or do { bmwqemu::fctwarn("sysread failed: $!") if is_debug and return undef };
    $cjx->incr_parse($qbuffer);
    return undef;
}

# utility function
sub read_json ($socket, $cmd_token = undef, $multi = undef) {
    my $cjx = Cpanel::JSON::XS->new->utf8;

    my $fd = fileno($socket);
    bmwqemu::diag("read_json($fd)") if is_debug;
    if (exists $sockets->{$fd}) {
        # start with the trailing text from previous call
        my $buffer = delete $sockets->{$fd};
        $cjx->incr_parse($buffer);
    }

    my $select = IO::Select->new();
    $select->add($socket);

    my @results;

    # the goal here is to find the end of the next valid JSON - and don't
    # add more data to it. As the backend sends things unasked, we might
    # run into the next message otherwise
    do { } until do_read_json ($cjx, $multi, $fd, $socket, $select, $cmd_token, \@results);
    return $multi ? @results : $results[0];
}

###################################################################
# enable send_json to send regular expressions
#<<< perltidy off
# this has to be on two lines so other tools don't believe this file
# exports package Regexp
package
Regexp;
#>>> perltidy on
sub TO_JSON ($regex) {
    $regex = "$regex";
    return $regex;
}

1;
