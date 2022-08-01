package CoverArtArchive::Indexer::EventHandler::Index;
use Moose;

use DBIx::Simple;
use JSON::XS;
use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::PutObject;
use Types::Serialiser;

with 'CoverArtArchive::Indexer::EventHandler';

sub queue { 'index' }

my $json = JSON::XS->new->utf8->canonical;

sub handle {
    my ($self, $release_gid) = @_;

    my $dbh = get_dbh($self->config->{database});

    my $release = $dbh->query(
        'SELECT release.name, release.barcode,
           artist_credit.name artist, release.gid, release.id
         FROM musicbrainz.release
         JOIN musicbrainz.artist_credit ON artist_credit.id = release.artist_credit
         WHERE release.id IN (
             SELECT new_id FROM musicbrainz.release_gid_redirect
             WHERE gid = ?
             UNION
             SELECT id FROM musicbrainz.release
             WHERE gid = ?
         )',
        $release_gid, $release_gid
    )->hash;

    if ($release) {
        my $json = $json->encode({
            images => [
                map +{
                    types => $_->{types},
                    front => $_->{is_front} ? Types::Serialiser::true : Types::Serialiser::false,
                    back => $_->{is_back} ? Types::Serialiser::true : Types::Serialiser::false,
                    comment => $_->{comment},
                    image => image_url($release->{gid}, $_->{id}, undef, $_->{suffix}),
                    thumbnails => {
                        small => image_url($release->{gid}, $_->{id}, 250, 'jpg'),
                        large => image_url($release->{gid}, $_->{id}, 500, 'jpg'),
                        '250' => image_url($release->{gid}, $_->{id}, 250, 'jpg'),
                        '500' => image_url($release->{gid}, $_->{id}, 500, 'jpg'),
                        '1200' => image_url($release->{gid}, $_->{id}, 1200, 'jpg'),
                    },
                    approved => $_->{approved} ? Types::Serialiser::true : Types::Serialiser::false,
                    edit => $_->{edit},
                    id => $_->{id}
                }, $dbh->query(
                    'SELECT * FROM cover_art_archive.index_listing
                     JOIN cover_art_archive.image_type USING (mime_type)
                     WHERE release = ?
                     ORDER BY ordering',
                    $release->{id}
                )->hashes
            ],
            release => 'https://musicbrainz.org/release/' . $release->{gid}
        });

        log_debug { "Produced $json" };
        $dbh->disconnect;

        {
            my $res = $self->lwp->request(
                Net::Amazon::S3::Request::PutObject->new(
                    s3      => $self->s3,
                    bucket  => 'mbid-' . $release->{gid},
                    key     => 'index.json',
                    value   => $json,
                    headers => {
                        'x-archive-meta-collection' => 'coverartarchive',
                        'x-archive-meta-mediatype' => 'image',
                        'x-archive-meta-noindex' => 'true',
                        "x-archive-auto-make-bucket" => 1,
                        "x-archive-keep-old-version" => 1,
                        'Content-Type' => 'application/json; charset=utf-8',
                    }
                )->http_request
            );

            if ($res->is_success) {
                log_info { "Upload of index.json succeeded" };
            }
            else {
                die "Upload of index.json failed: " . $res->decoded_content;
            }
        }

        {
            my $mb_uri = sprintf('http://musicbrainz.org/ws/2/release/%s?inc=artists', $release->{gid});
            my $mb_res = $self->lwp->get($mb_uri);
            unless ($mb_res->is_success) {
                die "Request for $mb_uri failed (" . $mb_res->code . "): " . $mb_res->decoded_content;
            }

            my $res = $self->lwp->request(
                Net::Amazon::S3::Request::PutObject->new(
                    s3      => $self->s3,
                    bucket  => 'mbid-' . $release->{gid},
                    key     => 'mbid-' . $release->{gid} . '_mb_metadata.xml',
                    value   => $mb_res->content,
                    headers => {
                        'x-archive-meta-collection' => 'coverartarchive',
                        'x-archive-meta-mediatype' => 'image',
                        'x-archive-meta-noindex' => 'true',
                        "x-archive-auto-make-bucket" => 1,
                        'Content-Type' => 'application/xml; charset=utf-8',
                    }
                )->http_request
            );

            if ($res->is_success) {
                log_info { "Upload of metadata.xml succeeded" };
            }
            else {
                die "Upload of metadata.xml failed: " . $res->decoded_content;
            }
        }
    }
    else {
        log_debug { "Release $release_gid does not exist, skipping indexing" };
        $dbh->disconnect;
    }
}

sub image_url {
    my ($mbid, $id, $size, $extension) = @_;
    my $urlsize = defined($size) ? "-$size" : '';

    return "http://coverartarchive.org/release/$mbid/$id$urlsize.$extension";
}

sub get_dbh {
    my ($config) = @_;

    my ($db_name, $db_host, $db_port, $db_user, $db_pass) =
        @{$config}{qw( database host port user password )};

    my $dbh = DBIx::Simple->connect(
        "dbi:Pg:dbname=$db_name;host=$db_host;port=$db_port",
        $db_user,
        $db_pass,
        {
            client_encoding => 'UTF8',
            # Prepared statements don't play nice with pgbouncer's transaction
            # pooling mode. Setting pg_server_prepare to 0 prevents errors in
            # the form of
            # "ERROR:  prepared statement "dbdpg_p67_81" does not exist",
            # which can occur as queries are executed on different backends.
            pg_server_prepare => 0,
        },
    ) or die DBIx::Simple->error;
    return $dbh;
}

1;
