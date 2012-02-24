package CoverArtArchive::Indexer;
use Moose;

use CoverArtArchive::Indexer::EventHandler::Delete;
use CoverArtArchive::Indexer::EventHandler::Index;
use Log::Contextual qw( :log );
use Try::Tiny;

with 'CoverArtArchive::Indexer::UseContext';

has event_handlers => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        return {
            map {
                my $evh = $_->new( c => $self->c );
                ($evh->event_type => $evh)
            } qw(
                CoverArtArchive::Indexer::EventHandler::Delete
                CoverArtArchive::Indexer::EventHandler::Index
            )
        }
    },
    traits => [ 'Hash' ],
    handles => {
        get_event_handler => 'get'
    }
);

sub run {
    my $self = shift;
    while (1) {
        if (my $batch_id = $self->dbh->query('SELECT pgq.next_batch(?, ?)', 'CoverArtIndex', 'CoverArtIndexer')->list) {
            my @events = $self->dbh->query('SELECT * FROM pgq.get_batch_events(?)', $batch_id)->hashes;
            log_trace { sprintf "Refreshing %d releases", scalar(@events) };

            for my $event (@events) {
                my $evh = $self->get_event_handler($event->{ev_type});

                if (!$evh) {
                    log_error { sprintf "No event handler for %s, marking as failed", $event->{ev_type} };
                    $self->dbh->query('SELECT pgq.event_failed(?, ?, ?)', $batch_id, $event->{ev_id}, 'Unknown ev_type');
                    next;
                }
                else {
                    try {
                        $evh->handle_event($event);
                    }
                    catch {
                        log_error { sprintf "Error running event handler: %s", $_ };
                        $self->dbh->query('SELECT pgq.event_failed(?, ?, ?)', $batch_id, $event->{ev_id}, $_);
                    };
                }
            }

            $self->dbh->query('SELECT pgq.finish_batch(?)', $batch_id);
        }
        else {
            log_trace { "Nothing to do" };
            sleep(10);
        }
    }
}

1;
