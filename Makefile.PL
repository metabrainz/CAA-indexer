use strict;
use warnings;
use inc::Module::Install;

name 'caa-indexer';
version '1.0';

requires 'AnyEvent';
requires 'Config::Tiny';
requires 'DBD::Pg';
requires 'DBIx::Simple';
requires 'Getopt::Long';
requires 'JSON::Any';
requires 'Log::Contextual';
requires 'LWP::UserAgent';
requires 'Net::Amazon::S3';
requires 'Net::RabbitFoot';
requires 'Pod::Usage';
requires 'Try::Tiny';
requires 'XML::XPath';

auto_install;
WriteAll;
