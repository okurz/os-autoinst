#!/usr/bin/perl

use Test::Most;
use Test::Warnings ':report_warnings';
use Test::Exception;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use OpenQA::Isotovideo::Main qw(_get_version_string);  # SUT


#is usage(0), 'foo', 'can call usage';
#lives_ok { usage(0) } 'can call usage';
pass 'foo';

is _get_version_string(), 'foo', 'can call version string';

done_testing;
