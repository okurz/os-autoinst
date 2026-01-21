#!/usr/bin/perl
use strict;
use warnings;
use FindBin '$Bin';
@ARGV = ('^(OpenQA/|[^/]+\.pm$|script/)');
require "$Bin/00-compile-check.pl";