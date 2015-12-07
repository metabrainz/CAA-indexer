use utf8;
use Test::More tests => 5;
use Test::Mock::LWP::Dispatch;
use CoverArtArchive::Indexer::Context;
use CoverArtArchive::Indexer::EventHandler::Move;
use Net::Amazon::S3;
use LWP::UserAgent;
use Log::Contextual::SimpleLogger;
use Log::Contextual qw( :log ),
   -logger => Log::Contextual::SimpleLogger->new({ levels_upto => 'emergency' });

my $move_event = {
    'ev_data' => "1031598329\n" .
        "aff4a693-5970-4e2e-bd46-e2ee49c22de7\n" .
        "5ee38258-8dfa-4d79-b2aa-6bbfceaf6cce\n" .
        "png",
        'ev_type' => 'move',
        'ev_retry' => undef,
        'ev_extra3' => undef,
        'ev_extra2' => undef,
        'ev_txid' => '789367',
        'ev_extra1' => undef,
        'ev_time' => '2013-07-11 17:44:11.429064+02',
        'ev_id' => '10',
        'ev_extra4' => undef
};

my $s3 = Net::Amazon::S3->new(
        aws_access_key_id     => "test",
        aws_secret_access_key => "test",
        retry                 => 0
    );

my $ua = LWP::UserAgent->new;

# Merge into this release, so copy the image to this bucket.
$ua->map (qr/5ee38258-8dfa-4d79-b2aa-6bbfceaf6cce/, sub {
    my $request = shift;
    is ($request->method, 'PUT', 'Put request made to S3');
    like ($request->uri, qr/mbid-5ee38258-8dfa-4d79-b2aa-6bbfceaf6cce-1031598329.png$/, "Put request to correct file");

    return HTTP::Response->new( 200 );
});

$ua->map (qr/aff4a693-5970-4e2e-bd46-e2ee49c22de7/, sub {
    my $request = shift;
    is ($request->method, 'DELETE', 'Delete request made to S3');
    like ($request->uri, qr/mbid-aff4a693-5970-4e2e-bd46-e2ee49c22de7-1031598329.png$/, "Delete request for correct file");

    return HTTP::Response->new( 200 );
});


my $c = CoverArtArchive::Indexer::Context->new (
    dbh => undef,
    lwp => $ua,
    s3 => $s3,
    rabbitmq => 0);

my $event = CoverArtArchive::Indexer::EventHandler::Move->new (c => $c);

isa_ok ($event, 'CoverArtArchive::Indexer::EventHandler::Move');

$event->handle($move_event);

1;
