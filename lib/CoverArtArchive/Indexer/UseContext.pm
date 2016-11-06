package CoverArtArchive::Indexer::UseContext;
use Moose::Role;

has c => (
    is => 'ro',
    required => 1,
    handles => [qw( dbh lwp s3 config )]
);

1;
