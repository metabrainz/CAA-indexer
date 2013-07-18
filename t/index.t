use utf8;
use DBIx::Simple;
use Test::More tests => 21;
use Test::Mock::LWP::Dispatch;
use Test::MockObject;
use CoverArtArchive::Indexer::Context;
use CoverArtArchive::Indexer::EventHandler::Index;
use JSON::Any;
use Net::Amazon::S3;
use LWP::UserAgent;
use Log::Contextual::SimpleLogger;
use Log::Contextual qw( :log ),
   -logger => Log::Contextual::SimpleLogger->new({ levels_upto => 'emergency' });

my $index_event = {
    'ev_data' => 'aff4a693-5970-4e2e-bd46-e2ee49c22de7',
    'ev_type' => 'index',
    'ev_retry' => undef,
    'ev_extra3' => undef,
    'ev_extra2' => undef,
    'ev_txid' => '788962',
    'ev_extra1' => undef,
    'ev_time' => '2013-07-11 16:00:48.161626+02',
    'ev_id' => '1',
    'ev_extra4' => undef
};

my $s3 = Net::Amazon::S3->new(
        aws_access_key_id     => "test",
        aws_secret_access_key => "test",
        retry                 => 0
    );

my $ua = LWP::UserAgent->new;

# Merge into this release, so copy the image to this bucket.
$ua->map (qr/index.json$/, sub {
    my $request = shift;
    is ($request->method, 'PUT', 'Put request, writing index.json');

    my $json = JSON::Any->new( utf8 => 1 );
    my $data = $json->decode ($request->content);
    my $front = $data->{images}->[0];
    my $back = $data->{images}->[1];

    my $caa_prefix = "http://coverartarchive.org/release/aff4a693-5970-4e2e-bd46-e2ee49c22de7";
    is_deeply ($front->{types}, [ 'Front' ]);
    is ($front->{front}, 1, "Front image is primary front image");
    is ($front->{back}, 0, "Front image is not primary back image");
    is ($front->{comment}, '');
    is ($front->{id}, "1031598329");
    is ($front->{image}, "$caa_prefix/1031598329.jpg", "correct image filename");
    is ($front->{thumbnails}->{small}, "$caa_prefix/1031598329-250.jpg");
    is ($front->{thumbnails}->{large}, "$caa_prefix/1031598329-500.jpg");

    is_deeply ($back->{types}, [ 'Back' ]);
    is ($back->{front}, 0, "Back image is not primary front image");
    is ($back->{back}, 1, "Back image is primary back image");
    is ($back->{comment}, 'ping!');
    is ($back->{id}, "4644074265");
    is ($back->{image}, "$caa_prefix/4644074265.png", "correct image filename");
    is ($back->{thumbnails}->{small}, "$caa_prefix/4644074265-250.jpg");
    is ($back->{thumbnails}->{large}, "$caa_prefix/4644074265-500.jpg");

    return HTTP::Response->new( 200 );
});

$ua->map (qr,ws/2/release/aff4a693-5970-4e2e-bd46-e2ee49c22de7,, sub {
    my $request = shift;
    is ($request->method, 'GET', 'Get request, fetching release XML');

    return HTTP::Response->new(
        200, "OK", [ 'Content-Type', 'application/xml' ],
        '<metadata><release><title>the Love Bug</title></release></metadata>');
});

$ua->map (qr/mbid-aff4a693-5970-4e2e-bd46-e2ee49c22de7_mb_metadata.xml$/, sub {
    my $request = shift;
    is ($request->method, 'PUT', 'Put request, writing release xml');

    is ($request->content,
        '<metadata><release><title>the Love Bug</title></release></metadata>',
        'Wrote expected release metadata xml to S3');

    return HTTP::Response->new( 200 );
});

my $select_from_release_results = Test::MockObject->new ();
$select_from_release_results->set_always ('hash', {
    'artist' => 'm-flo',
    'name' => 'the Love Bug',
    'id' => 59662,
    'barcode' => '4988064451180',
    'gid' => 'aff4a693-5970-4e2e-bd46-e2ee49c22de7'
});

my $select_from_index_listing_results = Test::MockObject->new ();
$select_from_index_listing_results->set_list (
    'hashes',
     {
         'id' => '1031598329', 'mime_type' => 'image/jpeg',
         'release' => 59662, 'types' => [ 'Front' ],
         'is_back' => 0, 'is_front' => 1,
         'date_uploaded' => '2012-05-24 09:35:13.984115+02',
         'edit' => 1, 'ordering' => 1, 'approved' => 0,
         'edits_pending' => 0, 'comment' => '', 'suffix' => 'jpg'
     },
     {
         'id' => '4644074265', 'mime_type' => 'image/png',
         'release' => 59662, 'types' => [ 'Back' ],
         'is_back' => 1, 'is_front' => 0,
         'date_uploaded' => '2013-07-16 12:14:39.942118+02',
         'edit' => 2, 'ordering' => 2, 'approved' => 0,
         'edits_pending' => 1, 'comment' => 'ping!',  'suffix' => 'png'
     }
    );


my $dbh = Test::MockObject->new ();
$dbh->set_series ('query',
                      $select_from_release_results,
                      $select_from_index_listing_results
                  );

my $c = CoverArtArchive::Indexer::Context->new (
    dbh => $dbh,
    lwp => $ua,
    s3 => $s3);

my $event = CoverArtArchive::Indexer::EventHandler::Index->new (c => $c);
isa_ok ($event, 'CoverArtArchive::Indexer::EventHandler::Index');
$event->handle_event ($index_event);

1;
