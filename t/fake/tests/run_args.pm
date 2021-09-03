use Mojo::Base 'basetest', -signatures;
use strictures;

use base 'basetest';

sub run ($self, $rargs) {

    unless (defined $rargs) {
        die 'run_args not passed through';
    }
}
1;
