# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package tinycv;

use Mojo::Base -strict, -signatures;
use bmwqemu 'fctwarn';
use File::Basename;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw();
our $VERSION = '1.0';

my $rust_initialized = 0;

sub _init_rust_bridge () {
    return 1 if $rust_initialized;
    eval {
        require Inline::Python;
        my $core_path = $ENV{OS_AUTOINST_RUST_CORE_PATH} || 'rust/os-autoinst-core';
        Inline::Python::py_eval(<<"EOF");
import sys
import os
sys.path.insert(0, os.path.abspath('$core_path'))
try:
    import os_autoinst_core
except ImportError as e:
    raise ImportError(f"Could not import os_autoinst_core from {os.path.abspath('$core_path')}: {e}")
EOF
    };
    if ($@) {
        bmwqemu::fctwarn("Rust bridge init failed: $@");
        return 0;
    }
    $rust_initialized = 1;
    return 1;
}

sub new ($w, $h) {
    _init_rust_bridge();
    my $data = Inline::Python::py_call_function("os_autoinst_core", "new_image", $w, $h);
    return tinycv::Image->new($data);
}

sub read ($filename) {
    _init_rust_bridge();
    my $data = Inline::Python::py_call_function("os_autoinst_core", "read_image", $filename);
    return tinycv::Image->new($data);
}

sub from_ppm ($data) {
    return tinycv::Image->new($data);
}

package tinycv::Image;
use Mojo::Base -base, -signatures;
use Inline::Python;

has 'ppm_data';

sub new ($class, $data) {
    return $class->SUPER::new(ppm_data => $data);
}

sub search_needle ($self, $needle, $x, $y, $w, $h, $margin) {
    my $res = Inline::Python::py_call_function("os_autoinst_core", "match_needle", $self->ppm_data, $needle->ppm_data, $x, $y, $w, $h, $margin);
    return @$res if $res;
    return ();
}

sub write ($self, $filename) {
    eval { Inline::Python::py_call_function("os_autoinst_core", "save_image", $self->ppm_data, $filename) };
    return $@ ? 0 : 1;
}

sub copyrect ($self, $x, $y, $w, $h) {
    my $data = Inline::Python::py_call_function("os_autoinst_core", "copy_rect", $self->ppm_data, $x, $y, $w, $h);
    return tinycv::Image->new($data);
}

sub replacerect ($self, $x, $y, $w, $h, $r = 0, $g = 0, $b = 0) {
    my $data = Inline::Python::py_call_function("os_autoinst_core", "replace_rect", $self->ppm_data, $x, $y, $w, $h, $r, $g, $b);
    $self->ppm_data($data);
    return $self;
}

sub scale ($self, $w, $h) {
    my $data = Inline::Python::py_call_function("os_autoinst_core", "scale", $self->ppm_data, $w, $h);
    return tinycv::Image->new($data);
}

sub xres ($self) {
    if ($self->ppm_data =~ /^P6\n(\d+) (\d+)\n/) {
        return $1;
    }
    return 1024;
}

sub yres ($self) {
    if ($self->ppm_data =~ /^P6\n(\d+) (\d+)\n/) {
        return $2;
    }
    return 768;
}

sub write_with_thumbnail ($self, $filename) {
    $self->write($filename) or die "Unable to write '$filename'\n";

    my $thumb = $self->scale($self->xres() * 45 / $self->yres(), 45);
    my $dir = File::Basename::dirname($filename) . '/.thumbs';
    my $base = File::Basename::basename($filename);

    mkdir $dir;
    $thumb->write("$dir/$base") or die "Unable to write '$dir/$base'\n";
}

sub mean_square_error ($areas) {
    my $mse = 0.0;
    for my $area (@$areas) {
        my $err = 1 - $area->{similarity};
        $mse += $err * $err;
    }
    return $mse / scalar @$areas;
}

sub search_ ($self, $needle, $threshold, $search_ratio, $stopwatch = undef) {
    $threshold ||= 0.0;
    $search_ratio ||= 0.0;
    return undef unless $needle;

    my $needle_image = $needle->get_image;
    unless ($needle_image) {
        bmwqemu::fctwarn("skipping $needle->{name}: missing PNG");
        return undef;
    }
    $stopwatch->lap('**++ search__: get image') if $stopwatch;

    my $img = $self;
    my (@exclude, @match, @ocr);
    for my $area (@{$needle->{area}}) {
        push @exclude, $area if $area->{type} eq 'exclude';
        push @match, $area if $area->{type} eq 'match';
        push @ocr, $area if $area->{type} eq 'ocr';
    }

    if (@exclude) {
        $img = $self->copy;
        for my $exclude_area (@exclude) {
            $img->replacerect(@{$exclude_area}{qw(xpos ypos width height)});
        }
    }

    my $ret = {ok => 1, needle => $needle, area => []};
    for my $area (@match) {
        my $margin = int($area->{margin} + $search_ratio * (1024 - $area->{margin}));
        my ($sim, $xmatch, $ymatch) = $img->search_needle($needle_image, $area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}, $margin);

        my $ma = {
            similarity => $sim // 0,
            x => $xmatch // 0,
            y => $ymatch // 0,
            w => $area->{width},
            h => $area->{height},
            result => 'ok',
        };

        my $m = ($area->{match} || 96) / 100;
        if (($sim // 0) < $m - $threshold) {
            $ma->{result} = 'fail';
            $ret->{ok} = 0;
        }
        push @{$ret->{area}}, $ma;
    }

    $ret->{error} = mean_square_error($ret->{area});
    if ($ret->{ok}) {
        for my $ocr_area (@ocr) {
            $ret->{ocr} ||= [];
            my $ocr = ocr::tesseract($img, $ocr_area);
            push @{$ret->{ocr}}, $ocr;
        }
    }
    return $ret;
}

sub search ($self, $needle, $threshold = undef, $search_ratio = undef, $stopwatch = undef) {
    return undef unless $needle;

    $stopwatch->lap('Searching for needles') if $stopwatch;
    if (ref($needle) eq 'ARRAY') {
        my @candidates;
        for my $n (@$needle) {
            my $found = $self->search_($n, $threshold, $search_ratio, $stopwatch);
            push @candidates, $found if $found;
        }
        @candidates = sort { $b->{ok} <=> $a->{ok} || $a->{error} <=> $b->{error} } @candidates;
        my $best = (@candidates && $candidates[0]->{ok}) ? shift @candidates : undef;
        return wantarray ? ($best, \@candidates) : $best;
    } else {
        my $found = $self->search_($needle, $threshold, $search_ratio, $stopwatch);
        $stopwatch->lap("** search_: single needle: $needle->{name}") if $stopwatch;
        return undef unless $found;
        if (wantarray) {
            return $found->{ok} ? ($found, undef) : (undef, [$found]);
        }
        return undef unless $found->{ok};
        return $found;
    }
}

sub copy ($self) {
    return tinycv::Image->new($self->ppm_data);
}

1;
