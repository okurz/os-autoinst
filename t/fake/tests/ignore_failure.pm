use Mojo::Base 'basetest', -signatures;
use strictures;

sub run { }

sub test_flags {
    return {ignore_failure => 1, fatal => 0};
}

1;
