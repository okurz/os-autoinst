# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package log;

use Mojo::Base -strict;
use Carp;
use Mojo::File qw(path);
use Mojo::Log;
use POSIX 'strftime';
use Time::HiRes qw(gettimeofday);
use Time::Moment;
use Term::ANSIColor;
use common qw(result_dir);
use Exporter 'import';
our @EXPORT_OK = qw(logger init_logger diag fctres fctinfo fctwarn modstate);

our $logger;
our $direct_output;

sub logger { $logger //= Mojo::Log->new(level => 'debug', format => \&log_format_callback) }

sub init_logger { logger->path(path(common::result_dir, 'autoinst-log.txt')) unless $direct_output }

sub update_line_number {
    return unless $autotest::current_test;
    return unless $autotest::current_test->{script};
    my @out;
    my $casedir = $bmwqemu::vars{CASEDIR} // '';
    for (my $i = 10; $i > 0; $i--) {
        my ($package, $filename, $line, $subroutine) = caller($i);
        next unless $filename && $filename =~ /\Q$casedir/;
        $filename =~ s@$casedir/?@@;
        push @out, "$filename:$line called $subroutine";
    }
    $log::logger->debug(join(' -> ', @out));
    return;
}

# pretty print like Data::Dumper but without the "VAR1 = " prefix
sub pp {
    # FTR, I actually hate Data::Dumper.
    my $value_with_trailing_newline = Data::Dumper->new(\@_)->Terse(1)->Useqq(1)->Dump();
    chomp($value_with_trailing_newline);
    return $value_with_trailing_newline;
}

sub log_call {
    my $fname = (caller(1))[3];
    update_line_number();
    my $params;
    if (@_ == 1) {
        $params = pp($_[0]);
    }
    else {
        # key/value pairs
        my @result;
        while (my ($key, $value) = splice(@_, 0, 2)) {
            if ($key =~ tr/0-9a-zA-Z_//c) {
                # only quote if needed
                $key = pp($key);
            }
            push @result, join("=", $key, pp($value));
        }
        $params = join(", ", @result);
    }
    logger->debug('<<< ' . $fname . "($params)");
    return;
}

sub log_format_callback {
    my ($time, $level, @items) = @_;

    my $lines = join("\n", @items, '');

    # ensure indentation for multi-line output
    $lines =~ s/(?<!\A)^/  /gm;

    return '[' . Time::Moment->now . "] [$level] $lines";
}

sub diag {
    my ($args) = @_;
    confess "missing input" unless $args;
    logger->append(color('white'));
    logger->debug(@_)->append(color('reset'));
    return;
}

sub fctres {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('green'));
    logger->debug(">>> $fname: $text")->append(color('reset'));
    return;
}

sub fctinfo {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('yellow'));
    logger->info("::: $fname: $text")->append(color('reset'));
    return;
}

sub fctwarn {
    my ($text, $fname) = @_;

    $fname //= (caller(1))[3];
    logger->append(color('red'));
    logger->warn("!!! $fname: $text")->append(color('reset'));
    return;
}

sub modstate {
    logger->append(color('bold blue'));
    logger->debug("||| @{[join(' ', @_)]}")->append(color('reset'));
    return;
}

1;
