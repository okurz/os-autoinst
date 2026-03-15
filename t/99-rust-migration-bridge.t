#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Feature::Compat::Try;
use Test::Warnings ':report_warnings';

BEGIN {
    try {
        require Inline::Python;
    } catch ($e) {
        plan skip_all => 'Inline::Python is not available';
    }
}

# Add the Rust library output directory to sys.path so Python can find it
Inline::Python::py_eval(<<'EOF');
import sys
import os

sys.path.insert(0, os.path.abspath('rust/os-autoinst-core'))

try:
    import os_autoinst_core

    def make_ppm(width, height, fill_color, rect=None):
        # fill_color is (r, g, b)
        # rect is (x, y, w, h, (r, g, b))
        header = f"P6\n{width} {height}\n255\n".encode('ascii')
        pixels = bytearray()
        for y in range(height):
            for x in range(width):
                if rect and rect[0] <= x < rect[0]+rect[2] and rect[1] <= y < rect[1]+rect[3]:
                    pixels.extend(rect[4])
                else:
                    pixels.extend(fill_color)
        return header + pixels
    
    def run_match_test():
        screen = make_ppm(100, 100, (0, 0, 0), rect=(10, 20, 10, 10, (255, 255, 255)))
        needle = make_ppm(100, 100, (0, 0, 0), rect=(10, 20, 10, 10, (255, 255, 255)))
        # Updated signature: match_needle(screen, needle, x, y, w, h, margin)
        res = os_autoinst_core.match_needle(screen, needle, 10, 20, 10, 10, 5)
        return list(res) if res is not None else None
    
    # Expose helper to global scope for py_eval
    globals()['make_ppm'] = make_ppm
    globals()['run_match_test'] = run_match_test

except ImportError as e:
    print(f"Failed to import rust core: {e}")
EOF

my $can_import = Inline::Python::py_eval('1 if "os_autoinst_core" in sys.modules else 0', 0);
plan skip_all => 'Failed to import os_autoinst_core module' unless $can_import;

# Test the sum_as_string method
my $sum_res = Inline::Python::py_eval('os_autoinst_core.sum_as_string(10, 20)', 0);
is $sum_res, '30', 'Rust core sum_as_string works through Python bridge';

# Test the match_needle method with real PPM images
my $match_res = Inline::Python::py_eval('run_match_test()', 0);
is ref($match_res), 'ARRAY', 'Rust match_needle returns an array tuple';
is_deeply $match_res, [1, 10, 20], 'Rust template matching finds exact sub-image at correct coordinates';

done_testing;
