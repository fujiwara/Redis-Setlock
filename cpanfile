requires 'perl', '5.008001';
requires 'Redis';
requires 'Log::Minimal';
requires 'Pod::Usage';
requires 'Try::Tiny';
requires 'Time::HiRes';
requires 'Guard';
requires 'Getopt::Long', '2.42';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::RedisServer';
    requires 'Net::EmptyPort';
    requires 'Test::SharedFork';
};


