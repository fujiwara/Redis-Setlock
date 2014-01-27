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

use constant {
    EXIT_CODE_REDIS_DEAD                => 1,
    EXIT_CODE_REDIS_UNSUPPORTED_VERSION => 2,
    EXIT_CODE_CANNOT_GET_LOCK           => 3,
};

use constant UNLOCK_LUA_SCRIPT => <<'END_OF_SCRIPT'
if redis.call("get",KEYS[1]) == ARGV[1]
then
    return redis.call("del",KEYS[1])
else
    return 0
end
END_OF_SCRIPT
;

sub parse_options {
    my (@argv) = @_;

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
        version
    /) or pod2usage;

    if ($opt->{version}) {
        print STDERR "version: $VERSION\n";
        exit 0;
    }
    $opt->{wait}      = 0 if $opt->{n};  # no delay
    $opt->{exit_code} = 0 if $opt->{x};  # exit code 0
    $opt->{expires}   = $DEFAULT_EXPIRES unless defined $opt->{expires};

    return ($opt, @argv);
}

sub run {
    my $class = shift;

    local $Log::Minimal::PRINT = \&log_minimal_print;

    my ($opt, $key, @command) = parse_options(@_);

    pod2usage() if !defined $key || @command == 0;

    my $redis = connect_to_redis_server($opt)
        or return EXIT_CODE_REDIS_DEAD;

    validate_redis_version($redis)
        or return EXIT_CODE_REDIS_UNSUPPORTED_VERSION;

    if ( my $token = try_get_lock($redis, $opt, $key) ) {
        my $code = invoke_command(@command);
        release_lock($redis, $opt, $key, $token);
        return $code;
    }
    else {
        # couldnot get lock
        if ($opt->{exit_code}) {
            critf "unable to lock %s.", $key;
            return $opt->{exit_code};
        }
        return 0; # by option x
    }
}

sub connect_to_redis_server {
    my $opt = shift;
    try {
        Redis->new(
            server    => $opt->{redis},
            reconnect => $opt->{wait} ? $opt->{expires} : 0,
        );
    }
    catch {
        my $e = $_;
        my $error = (split(/\n/, $e))[0];
        critf "Redis server seems down: %s", $error;
        return;
    };
}

sub validate_redis_version {
    my $redis = shift;
    my $version = $redis->info->{redis_version};
    debugf "Redis version is: %s", $version;
    my ($major, $minor, $rev) = split /\./, $version;
    if ( $major >= 3
      || $major == 2 && $minor >= 7
      || $major == 2 && $minor == 6 && $rev >= 12
    ) {
        # ok
        return 1;
    }
    critf "required Redis server version >= 2.6.12. current server version is %s", $version;
    return;
}

sub try_get_lock {
    my ($redis, $opt, $key) = @_;
    my $got_lock;
    my $token = create_token();
 GET_LOCK:
    while (1) {
        my @args = ($key, $token, "EX", $opt->{expires}, "NX");
        debugf "redis: SET @args";
        $got_lock = $redis->set(@args);
        if ($got_lock) {
            debugf "got lock: %s", $key;
            last GET_LOCK;
        }
        elsif (!$opt->{wait}) { # no delay by option n
            debugf "no delay mode. exit";
            last GET_LOCK;
        }
        else {
            my $sleep = rand();
            debugf "unable to lock. retry after %f sec.", $sleep;
            sleep $sleep;
        }
    }
    return $token if $got_lock;
}

sub release_lock {
    my ($redis, $opt, $key, $token) = @_;
    if ($opt->{keep}) {
        debugf "Keep lock key %s", $key;
    }
    else {
        debugf "Release lock key %s", $key;
        $redis->eval(UNLOCK_LUA_SCRIPT, 1, $key, $token);
    }
}

sub invoke_command {
    my @command = @_;
    debugf "invoking command: @command";
    my $code = system @command;
    $code = $code >> 8;       # to raw exit code
    debugf "child exit with code: %s", $code;
    return $code;
}

sub log_minimal_print {
    my ( $time, $type, $message, $trace) = @_;
    warn "$time $$ $type $message\n";
}

sub create_token {
    Time::HiRes::time() . rand();
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

=head1 REQUIREMENTS

Redis Server >= 2.6.12.

=head1 LICENSE

Copyright (C) FUJIWARA Shunichiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

FUJIWARA Shunichiro E<lt>fujiwara.shunichiro@gmail.comE<gt>

=cut

