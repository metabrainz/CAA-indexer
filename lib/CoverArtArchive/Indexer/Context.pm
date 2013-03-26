package CoverArtArchive::Indexer::Context;
use Moose;

has s3 => (
    is => 'ro',
    required => 1
);

has lwp => (
    is => 'ro',
    required => 1,
);

has dbh => (
    is => 'ro',
    required => 1
);

has rabbitmq => (
    is => 'ro',
    required => 1
);

__PACKAGE__->meta->make_immutable;
1;
