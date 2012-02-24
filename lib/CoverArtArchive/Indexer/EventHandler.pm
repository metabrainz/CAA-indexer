package CoverArtArchive::Indexer::EventHandler;
use Moose::Role;

with 'CoverArtArchive::Indexer::UseContext';

requires '_build_event_type', 'handle_event';

has event_type => (
    isa => 'Str',
    is => 'ro',
    builder => '_build_event_type',
    lazy => 1,
    required => 1
);

1;
