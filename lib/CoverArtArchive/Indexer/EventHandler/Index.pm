package CoverArtArchive::Indexer::EventHandler::Index;
use Moose;

use JSON::Any;
use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::PutObject;

with 'CoverArtArchive::Indexer::EventHandler';

sub queue { 'index' }

my $json = JSON::Any->new( utf8 => 1 );

sub handle {
    my ($self, $release_gid) = @_;

    my $release = $self->dbh->query(
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
        my $json = $json->objToJson({
            images => [
                map +{
                    types => $_->{types},
                    front => $_->{is_front} ? JSON::Any->true : JSON::Any->false,
                    back => $_->{is_back} ? JSON::Any->true : JSON::Any->false,
                    comment => $_->{comment},
                    image => image_url($release->{gid}, $_->{id}, undef, $_->{suffix}),
                    thumbnails => {
                        small => image_url($release->{gid}, $_->{id}, 250, 'jpg'),
                        large => image_url($release->{gid}, $_->{id}, 500, 'jpg'),
                    },
                    approved => $_->{approved} ? JSON::Any->true : JSON::Any->false,
                    edit => $_->{edit},
                    id => $_->{id}
                }, $self->dbh->query(
                    'SELECT * FROM cover_art_archive.index_listing
                     JOIN cover_art_archive.image_type USING (mime_type)
                     WHERE release = ?
                     ORDER BY ordering',
                    $release->{id}
                )->hashes
            ],
            release => 'http://musicbrainz.org/release/' . $release->{gid}
        });

        log_debug { "Produced $json" };

        {
            my $res = $self->lwp->request(
                Net::Amazon::S3::Request::PutObject->new(
                    s3      => $self->s3,
                    bucket  => 'mbid-' . $release->{gid},
                    key     => 'index.json',
                    value   => $json,
                    headers => {
                        'x-archive-meta-collection' => 'coverartarchive',
                        "x-archive-auto-make-bucket" => 1,
                        'Content-Type' => 'application/json; charset=utf-8'
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
            my $res = $self->lwp->request(
                Net::Amazon::S3::Request::PutObject->new(
                    s3      => $self->s3,
                    bucket  => 'mbid-' . $release->{gid},
                    key     => 'mbid-' . $release->{gid} . '_mb_metadata.xml',
                    value   => $self->lwp->get(
                        sprintf('http://musicbrainz.org/ws/2/release/%s?inc=artists', $release->{gid})
                    )->content,
                    headers => {
                        'x-archive-meta-collection' => 'coverartarchive',
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
    }
}

sub image_url {
    my ($mbid, $id, $size, $extension) = @_;
    my $urlsize = defined($size) ? "-$size" : '';

    return "http://coverartarchive.org/release/$mbid/$id$urlsize.$extension";
}

1;
