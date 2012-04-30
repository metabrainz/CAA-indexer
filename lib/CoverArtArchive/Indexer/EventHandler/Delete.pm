package CoverArtArchive::Indexer::EventHandler::Delete;
use Moose;

use Log::Contextual qw( :log );
use Net::Amazon::S3::Request::DeleteObject;

with 'CoverArtArchive::Indexer::EventHandler';

sub _build_event_type { 'delete' }

sub handle_event {
    my ($self, $event) = @_;
    my ($id, $mbid) = split /\n/, $event->{ev_data};

    if (!$id || !$mbid) {
        die "Event does not contain sufficient data";
    }

    my $key = $id eq 'index.json' ? $id : "mbid-$mbid-$id.jpg";

    my $req = Net::Amazon::S3::Request::DeleteObject->new(
        s3      => $self->s3,
        bucket  => "mbid-$mbid",
        key     => $key
    )->http_request;

    my $res = $self->lwp->request($req);

    if ($res->is_success) {
        log_info { "Successfuly deleted $mbid/$key" };
    }
    else {
        die "Delete of $key failed: " . $res->decoded_content;
    }
}

__PACKAGE__->meta->make_immutable;
1;
