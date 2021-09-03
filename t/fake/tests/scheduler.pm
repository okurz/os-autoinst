use Mojo::Base 'basetest', -signatures;
use strictures;
use autotest 'loadtest';

sub run {
    loadtest 'tests/next.pm';
}
1;
