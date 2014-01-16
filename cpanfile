requires 'perl', '5.008001';
requires 'Redis';
requires 'Log::Minimal';
requires 'Pod::Usage';

on 'test' => sub {
    requires 'Test::More', '0.98';
};


