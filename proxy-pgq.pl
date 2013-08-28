#!/usr/bin/env perl

use strict;
use warnings;

use Config::Tiny;
use DBIx::Simple;
use Net::RabbitFoot;

my $config_file = !@ARGV || $_[0] =~ /^-/
        ? 'config.ini'
        : shift();

my $config = Config::Tiny->read($config_file);

my $db_name = $config->{database}{database};
my $db_user = $config->{database}{user};
my $db_host = $config->{database}{host};
my $db_port = $config->{database}{port};
my $db_pass = $config->{database}{password};

my $dbh = DBIx::Simple->connect(
    "dbi:Pg:host=$db_host;dbname=$db_name;port=$db_port", $db_user, $db_pass)
    or die DBIx::Simple->error;

my $rabbitmq = Net::RabbitFoot->new->load_xml_spec->connect(
    map { $_ => $config->{rabbitmq}{$_} } qw ( host port user pass vhost )
) or die "Could not connect";

my $chan = $rabbitmq->open_channel or die "Could not open RabbitMQ connection";

while (1) {
    if (
        my $batch_id = $dbh->query(
            'SELECT pgq.next_batch(?, ?)', 'CoverArtIndex', 'Proxy'
        )->list
    ) {
        my @events = $dbh->query(
            'SELECT * FROM pgq.get_batch_events(?)', $batch_id
        )->hashes;

        for my $event (@events) {
            $rabbitmq->publish(
                routing_key => $event->{ev_type},
                body => $event->{ev_data},
                exchange => 'cover-art-archive',
            );
        }

        $dbh->query('SELECT pgq.finish_batch(?)', $batch_id);
    }
    else {
        sleep 10;
    }
}
