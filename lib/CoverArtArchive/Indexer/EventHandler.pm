package CoverArtArchive::Indexer::EventHandler;
use Moose::Role;

with 'CoverArtArchive::Indexer::UseContext';

requires 'handle', 'queue';

1;
