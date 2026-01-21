#!/usr/bin/perl
use strict;
use warnings;
use FindBin '$Bin';
@ARGV = ('^t/');
require "$Bin/00-compile-check.pl";