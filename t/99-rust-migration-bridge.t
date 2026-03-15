use strict;
use warnings;
use Test::Most;

BEGIN {
    eval { require Inline::Python };
    plan skip_all => 'Inline::Python is not available' if $@;
}

# Add the Rust library output directory to sys.path so Python can find it
Inline::Python::py_eval(<<'EOF');
import sys
import os

sys.path.insert(0, os.path.abspath('rust/os-autoinst-core'))

try:
    import os_autoinst_core
except ImportError as e:
    print(f"Failed to import rust core: {e}")
EOF

my $can_import = Inline::Python::py_eval('1 if "os_autoinst_core" in sys.modules else 0', 0);
plan skip_all => 'Failed to import os_autoinst_core module' unless $can_import;

plan tests => 2;

# Test the sum_as_string method
my $sum_res = Inline::Python::py_eval('os_autoinst_core.sum_as_string(10, 20)', 0);
is $sum_res, '30', 'Rust core sum_as_string works through Python bridge';

# Test the match_needle method with dummy data
my $match_res = Inline::Python::py_eval('os_autoinst_core.match_needle(b"screen", b"needle")', 0);
is $match_res, 1, 'Rust core match_needle works through Python bridge';
