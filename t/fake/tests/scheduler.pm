use Mojo::Base -strict, -signatures;
use strictures;
use base 'basetest';
use autotest 'loadtest';

sub run {
    loadtest 'tests/next.pm';
}
1;
