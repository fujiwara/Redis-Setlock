package Redis::Setlock;
use 5.008001;
use strict;
use warnings;
use Redis;
use Getopt::Long ();
use Pod::Usage;
use Log::Minimal;
use Try::Tiny;
use Time::HiRes qw/ sleep /;

our $VERSION            = "0.01";
our $DEFAULT_EXPIRES    = 86400;
our $LOCK_WAIT_INTERVAL = 1;

use constant {
    EXIT_CODE_REDIS_DEAD                => 1,
    EXIT_CODE_REDIS_UNSUPPORTED_VERSION => 2,
    EXIT_CODE_CANNOT_GET_LOCK           => 3,
};

sub parse_options {
    my ($class, @argv) = @_;

    my $p = Getopt::Long::Parser->new(
        config => [qw/posix_default no_ignore_case auto_help bundling pass_through/]
    );
    my $opt = {
        wait      => 1,
        exit_code => EXIT_CODE_CANNOT_GET_LOCK,
    };
    $p->getoptionsfromarray(\@argv, $opt, qw/
        redis=s
        expires=i
        keep
        n
        N
        x
        X
    /) or pod2usage;
    $opt->{wait}      = 0 if $opt->{n};  # no lock
    $opt->{exit_code} = 0 if $opt->{x};  # exit code 0

    return ($opt, @argv);
}

sub run {
    my $class = shift;

    local $Log::Minimal::PRINT = sub {
        my ( $time, $type, $message, $trace) = @_;
        warn "$time $$ $type $message\n";
    };

    my ($opt, $key, @argv) = $class->parse_options(@_);

    pod2usage() if !defined $key || @argv == 0;

    my $r = try {
        Redis->new(
            server    => $opt->{redis},
            reconnect => $opt->{wait} ? $DEFAULT_EXPIRES : 0,
        );
    } catch {
        my $e = $_;
        critf "Redis server seems down: %s", $e;
        return EXIT_CODE_REDIS_DEAD;
    };
    my $redis;
    if (ref $r) {
        $redis = $r;
    }
    else {
        return $r;
    }

    my $version = $redis->info->{redis_version};
    debugf "Redis version is: %s", $version;
    my ($major, $minor, $rev) = split /\./, $version;
    if ( $major >= 3
      || $major == 2 && $minor >= 7
      || $major == 2 && $minor == 6 && $rev >= 12
    ) {
        # ok
    }
    else {
        critf "required Redis server version >= 2.6.12. current server version is %s", $version;
        return EXIT_CODE_REDIS_UNSUPPORTED_VERSION;
    }

    my $expires = $opt->{expires} || $DEFAULT_EXPIRES;
    my $locked;
    while (1) {
        my @command = ($key, time, "EX", $expires, "NX");
        debugf "redis: set @command";
        my $r = $redis->set(@command);
        if ($r) {
            $locked = 1;
            debugf "Got lock: %s", $key;
            last;
        }
        debugf "result: %s", defined $r ? $r : "";
        if (!$opt->{wait}) { # no wait by option n
            debugf "No wait mode. exit";
            last;
        }
        debugf "Can't get lock. retry after %d sec.", $LOCK_WAIT_INTERVAL;
        sleep $LOCK_WAIT_INTERVAL;
    }
    if ($locked) {
        debugf "invoking command: @argv";
        my $code = system @argv;
        $code = $code >> 8;       # to raw exit code
        debugf "child exit with code: %s", $code;
        if ($opt->{keep}) {
            debugf "Keep lock key %s", $key;
        }
        else {
            debugf "Release lock key %s", $key;
            $redis->del($key);
        }
        return $code;
    }
    else {
        # can't get lock
        if ($opt->{exit_code}) {
            critf "Can't get lock key %s. died.", $key;
            return $opt->{exit_code};
        }
        return 0; # by option x
    }
}

1;
__END__

=encoding utf-8

=for stopwords setlock

=head1 NAME

Redis::Setlock - Like the setlock command using Redis.

=head1 SYNOPSIS

    $ redis-setlock [-nNxX] KEY program [ arg ... ]

    --redis (Default: 127.0.0.1:6379): redis-host:redis-port
    --expires (Default: 86400): The lock will be auto-released after the expire time is reached.
    --keep: Keep the lock after invoked command exited.
    -n: No delay. If KEY is locked by another process, redis-setlock gives up.
    -N: (Default.) Delay. If KEY is locked by another process, redis-setlock waits until it can obtain a new lock.
    -x: If KEY is locked, redis-setlock exits zero.
    -X: (Default.) If KEY is locked, redis-setlock prints an error message and exits nonzero.

=head1 DESCRIPTION

Redis::Setlock is a like the setlock command using Redis.

=head1 LICENSE

Copyright (C) FUJIWARA Shunichiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

FUJIWARA Shunichiro E<lt>fujiwara.shunichiro@gmail.comE<gt>

=cut

