#!/usr/bin/perl
use strict;
use warnings;
use FindBin '$Bin';
@ARGV = ('^(backend/|consoles/)');
require "$Bin/00-compile-check.pl";