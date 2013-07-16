use strict;
use warnings;
use inc::Module::Install;

name 'caa-indexer';
version '1.0';

requires 'Config::Tiny';
requires 'DBD::Pg';
requires 'DBIx::Simple';
requires 'Getopt::Long';
requires 'JSON::Any';
requires 'Log::Contextual';
requires 'LWP::UserAgent';
requires 'Net::Amazon::S3';
requires 'Pod::Usage';
requires 'Try::Tiny';
requires 'XML::XPath';

requires 'Test::More';
requires 'Test::Mock::LWP::Dispatch';
requires 'Test::MockObject';

auto_install;
WriteAll;
