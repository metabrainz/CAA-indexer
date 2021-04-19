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
                "x-archive-meta-mediatype" => 'image',
                "x-archive-meta-noindex" => 'true',
                "x-archive-keep-old-version" => 1,
            },
            value => ''
        )->http_request
    );

    if (!$res->is_success) {
        die "Copying of $old_mbid/$id to $new_mbid/$id failed: " .
            $res->decoded_content;
    }

    # Delete the old image
    my $req = Net::Amazon::S3::Request::DeleteObject->new(
        s3 => $self->s3,
        bucket => "mbid-$old_mbid",
        key => "mbid-$old_mbid-$id.$suffix",
    )->http_request;

    # Net::Amazon::S3::Request::DeleteObject does not support a headers
    # attribute, unlike the other Net::Amazon::S3::Request::* packages.
    $req->header('x-archive-keep-old-version' => 1);

    $self->c->lwp->request($req);
}

1;
