package CoverArtArchive::Indexer::EventHandler::Index;
use Moose;

use JSON::Any;
use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::PutObject;

with 'CoverArtArchive::Indexer::EventHandler';

sub _build_event_type { 'index' }

my $json = JSON::Any->new( utf8 => 1 );

sub handle_event {
    my ($self, $event) = @_;

    my $release_gid = $event->{ev_data};

    my $release = $self->dbh->query(
        'SELECT name.name, release.barcode, ac_name.name artist, release.gid, release.id
         FROM musicbrainz.release
         JOIN musicbrainz.release_name name ON name.id = release.name
         JOIN musicbrainz.artist_credit ON artist_credit.id = release.artist_credit
         JOIN musicbrainz.artist_name ac_name ON ac_name.id = artist_credit.name
         WHERE release.id IN (
             SELECT new_id FROM musicbrainz.release_gid_redirect
             WHERE gid = ?
             UNION
             SELECT id FROM musicbrainz.release
             WHERE gid = ?
         )',
        $release_gid, $release_gid
    )->hash;

    # There are 3 possibilities
    # 1. The release has been changed, we only need to reindex
    if ($release && $release->{gid} eq $release_gid) {
        my $json = $json->objToJson({
            images => [
                map +{
                    types => [
                        $self->dbh->query(
                            'SELECT art_type.name
                             FROM cover_art_archive.cover_art_type
                             JOIN cover_art_archive.art_type ON cover_art_type.type_id = art_type.id
                             WHERE cover_art_type.id = ?',
                            $_->{id})->flat
                    ],
                    front => $_->{is_front} ? JSON::Any->true : JSON::Any->false,
                    back => $_->{is_back} ? JSON::Any->true : JSON::Any->false,
                    comment => $_->{comment},
                    image => image_url($release->{gid}, $_->{id}),
                    thumbnails => {
                        small => image_url($release->{gid}, $_->{id}, 250),
                        large => image_url($release->{gid}, $_->{id}, 500),
                    },
                    approved => $_->{approved} ? JSON::Any->true : JSON::Any->false,
                    edit => $_->{edit}
                }, $self->dbh->query(
                    'SELECT cover_art.*,
                       (edit.close_time IS NOT NULL) AS approved
                     FROM cover_art_archive.cover_art
                     JOIN musicbrainz.edit ON edit.id = cover_art.edit
                     WHERE cover_art.release = ?
                     ORDER BY ordering',
                    $release->{id}
                )->hashes
            ],
            release => {
                title => $release->{name},
                artist => $release->{artist},
                barcode => $release->{barcode},
                catalognumbers => [
                    $self->dbh->query(
                        'SELECT DISTINCT catalog_number
                         FROM musicbrainz.release_label
                         WHERE catalog_number IS NOT NULL AND release = ?',
                        $release->{id})->flat
                    ]
            }
        });

        log_debug { "Produced $json" };

        my $res = $self->lwp->request(
            Net::Amazon::S3::Request::PutObject->new(
                s3      => $self->s3,
                bucket  => 'mbid-' . $release->{gid},
                key     => 'index.json',
                value   => $json,
                headers => {
                    'x-archive-meta-collection' => 'coverartarchive',
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
    # 2. The release has been merged into another release.
    elsif ($release && $release->{gid} ne $release_gid) {
        die "Merges are not yet supported";
    }
    # 3. The release has been entirely deleted, so everything should be removed
    else {
        die "Deleting releases is not yet supported";
    }
}

sub image_url {
    my ($mbid, $id, $size) = @_;
    my $suffix = defined($size) ? "-$size" : '';

    return "http://coverartarchive.org/release/$mbid/$id$suffix.jpg";
}

1;
