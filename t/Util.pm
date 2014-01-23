package t::Util;

use strict;
use warnings;
use Test::RedisServer;
use Net::EmptyPort qw/ empty_port wait_port /;
use Carp;
use Test::More;
use Time::HiRes qw/ sleep gettimeofday tv_interval /;

use Exporter 'import';
our @EXPORT_OK = qw/ redis_server redis_setlock /;

my $Perl    = $^X;
my $Command = "script/redis-setlock";

sub redis_server {
    my $redis_server;
    my $port = empty_port();
    eval {
        $redis_server = Test::RedisServer->new( conf => {
            port => $port,
            save => "",
        })
    } or plan skip_all => 'redis-server is required to this test';
    wait_port($port, 10);
    return $redis_server;
}

sub timer(&) {
    my $code_ref = shift;
    my $t0 = [ gettimeofday ];
    my $r = $code_ref->();
    my $elapsed = tv_interval($t0);
    return $r, $elapsed;
}

sub redis_setlock {
    my @args = @_;
    timer { Redis::Setlock->run(@args) };
}

1;
