package CoverArtArchive::Indexer::EventHandler::Move;
use Moose;

with 'CoverArtArchive::Indexer::EventHandler';

use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::DeleteObject;
use Net::Amazon::S3::Request::PutObject;

sub queue { 'move' }

sub handle {
    my ($self, $body) = @_;
    my ($id, $old_mbid, $new_mbid, $suffix) = split /\n/, $body;

    $suffix //= "jpg";

    log_trace { "Copying from $old_mbid/$id to $new_mbid" };

    # Copy the image to the new MBID
    my $res = $self->c->lwp->request(
        Net::Amazon::S3::Request::PutObject->new(
            s3      => $self->s3,
            bucket  => "mbid-$new_mbid",
            key     => join('-', 'mbid', $new_mbid, $id) . ".$suffix",
            headers => {
                'x-amz-copy-source' => "/mbid-$old_mbid/mbid-$old_mbid-$id.$suffix",
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
            key => "mbid-$old_mbid-$id.$suffix"
        )->http_request
    )
}

1;
