#!/usr/bin/perl

use Test::Most;
use Test::Warnings qw(warning :report_warnings);
use Mojo::Base -strict, -signatures;
use autodie ':all';
use Test::Output qw(combined_like);
use File::Path qw(remove_tree rmtree);
use Cwd 'abs_path';
use Mojo::File qw(tempdir path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '10';
use OpenQA::Isotovideo::CommandHandler;
use OpenQA::Isotovideo::Utils qw(load_test_schedule handle_generated_assets);

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $pool_dir = "$dir/pool";
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir $pool_dir;

subtest 'error handling when loading test schedule' => sub {
    chdir($dir);
    my $base_state = path(bmwqemu::STATE_FILE);
    subtest 'no schedule at all' => sub {
        $base_state->remove;
        $bmwqemu::vars{CASEDIR} = $bmwqemu::vars{PRODUCTDIR} = $dir;
        throws_ok { load_test_schedule } qr/'SCHEDULE' not set and/, 'error logged';
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'tests', 'state file contains component message');
            like($state->{msg}, qr/unable to load main\.pm/, 'state file contains error message');
        }
    };
    subtest 'unable to load test module' => sub {
        $base_state->remove;
        my $module = 'foo/bar';
        $bmwqemu::vars{SCHEDULE} = $module;
        combined_like {
            warning { throws_ok { load_test_schedule } qr/Can't locate $module\.pm/, 'error logged' }
        } qr/Can't locate $module\.pm/, 'debug message logged';
        my $state = decode_json($base_state->slurp);
        if (is(ref $state, 'HASH', 'state file contains object')) {
            is($state->{component}, 'tests', 'state file contains component');
            like($state->{msg}, qr/unable to load foo\/bar\.pm/, 'state file contains error message');
        }
    };
    subtest 'invalid productdir' => sub {
        $bmwqemu::vars{SCHEDULE} = undef;
        $bmwqemu::vars{PRODUCTDIR} = 'not/found';
        throws_ok { load_test_schedule } qr/PRODUCTDIR.*invalid/, 'error logged';
    };
};

subtest 'upload the asset even in an incomplete job' => sub {
    # mock backend/driver
    {
        package FakeBackendDriver;
        sub new ($class, $name) {
            my $self = bless({class => $class}, $class);
            require "backend/$name.pm";
            $self->{backend} = "backend::$name"->new();
            return $self;
        }
        sub extract_assets ($self, @args) { $self->{backend}->do_extract_assets(@args) }
    }

    my $command_handler = OpenQA::Isotovideo::CommandHandler->new();
    $bmwqemu::vars{BACKEND} = 'qemu';
    $bmwqemu::vars{NUMDISKS} = 1;
    $bmwqemu::vars{FORCE_PUBLISH_HDD_1} = 'force_publish_test.qcow2';
    $bmwqemu::vars{PUBLISH_HDD_1} = 'publish_test.qcow2';
    $command_handler->test_completed(0);
    $bmwqemu::backend = FakeBackendDriver->new('qemu');
    my $return_code;
    combined_like {
        $return_code = handle_generated_assets($command_handler, 1)
    } qr/Requested to force the publication/, 'forced publication of asset';
    my $base_state = path(bmwqemu::STATE_FILE);
    is $return_code, 0, 'The asset was uploaded successfully' or die $base_state->slurp;
    my $force_publish_asset = $pool_dir . '/assets_public/force_publish_test.qcow2';
    ok(-e $force_publish_asset, 'test.qcow2 image exists');
    ok(!-e $pool_dir . '/assets_public/publish_test.qcow2', 'the asset defined by PUBLISH_HDD_X would not be generated in an incomplete job');
};


done_testing;
