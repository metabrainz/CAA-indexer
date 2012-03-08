package CoverArtArchive::Indexer::EventHandler::Move;
use Moose;

with 'CoverArtArchive::Indexer::EventHandler';

use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::DeleteObject;
use Net::Amazon::S3::Request::PutObject;

sub _build_event_type { 'move' }

sub handle_event {
    my ($self, $event) = @_;
    my ($id, $old_mbid, $new_mbid) = split /\n/, $event->{ev_data};

    log_trace { "Copying from $old_mbid/$id to $new_mbid" };

    # Copy the image to the new MBID
    my $res = $self->c->lwp->request(
        Net::Amazon::S3::Request::PutObject->new(
            s3      => $self->s3,
            bucket  => "mbid-$new_mbid",
            key     => join('-', 'mbid', $new_mbid, $id) . '.jpg',
            headers => {
                'x-amz-copy-source' => "/ambid-$old_mbid/mbid-$old_mbid-$id.jpg",
                "x-archive-auto-make-bucket" => 1,
                "x-archive-meta-collection" => 'coverartarchive',
                "x-archive-meta-mediatype" => 'images',
            },
            value => ''
        )->http_request
    );

    # Delete the old image
    $self->c->lwp->request(
        Net::Amazon::S3::Request::DeleteObject->new(
            s3 => $self->s3,
            bucket => "mbid-$old_mbid",
            key => "mbid-$old_mbid-$id.jpg"
        )->http_request
    )
}

1;
