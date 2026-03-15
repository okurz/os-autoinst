# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package ocr;
use Mojo::Base -strict, -signatures;
use Mojo::File 'path';
require IPC::System::Simple;
use autotest qw(query_isotovideo);

use MIME::Base64 'encode_base64';

sub tesseract ($img, $area) {
    if ($ENV{OS_AUTOINST_RUST_CORE}) {
        # Use the bridge
        my $cropped = $area ? $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}) : $img;
        my $res = query_isotovideo('ocr', {screen => encode_base64($cropped->ppm_data)});
        return $res if defined $res;
    }

    my $imgfn = 'ocr.png';
    my $txtfn = 'ocr';    # tesseract appends .txt automatically o_O
    my $txt;
    $img = $img->copyrect($area->{xpos}, $area->{ypos}, $area->{width}, $area->{height}) if $area;
    $img->write($imgfn);
    # disable debug output, because new versions by default only reports errors and warnings
    system "tesseract $imgfn $txtfn quiet";
    $txtfn .= '.txt';
    $txt = path($txtfn)->slurp('UTF-8');
    unlink $imgfn;
    unlink $txtfn;
    return $txt;
}

1;
