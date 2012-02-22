use strict;
use warnings;
use DBIx::Simple;
use JSON::Any;
use Try::Tiny;

my $dbh = DBIx::Simple->connect('dbi:Pg:dbname=musicbrainz', 'musicbrainz');
my $json = JSON::Any->new( utf8 => 1 );

while(1) {
    if (my $batch_id = $dbh->query('SELECT pgq.next_batch(?, ?)', 'CoverArtIndex', 'CoverArtIndexer')->list) {
        my @events = $dbh->query('SELECT * FROM pgq.get_batch_events(?)', $batch_id)->hashes;
        printf STDERR "INFO: Refreshing %d releases\n", scalar(@events);

        for my $event (@events) {
            if ($event->{ev_type} ne 'index') {
                printf STDERR "ERROR: Encountered an event that was not of ev_type 'index'. Marking as failed\n";
                $dbh->query('SELECT pgq.event_failed(?, ?, ?)', $batch_id, $event->{ev_id}, 'Unknown ev_type');
                next;
            }

            try {
                my $release_id = $event->{ev_data};

                my $release = $dbh->query(
                    'SELECT name.name, release.barcode, ac_name.name artist
                     FROM musicbrainz.release
                     JOIN musicbrainz.release_name name ON name.id = release.name
                     JOIN musicbrainz.artist_credit ON artist_credit.id = release.artist_credit
                     JOIN musicbrainz.artist_name ac_name ON ac_name.id = artist_credit.name
                     WHERE release.id = ?',
                    $release_id
                )->hash;

                my $json = $json->objToJson({
                    release => {
                        title => $release->{name},
                        artist => $release->{artist},
                        barcode => $release->{barcode},
                        catalognumbers => [
                            $dbh->query(
                                'SELECT DISTINCT catalog_number
                                 FROM musicbrainz.release_label
                                 WHERE catalog_number IS NOT NULL AND release = ?',
                                $release_id)->flat
                        ]
                    }
                });

                printf STDERR "INFO: Produced %s\n", $json;
            }
            catch {
                printf STDERR "ERROR: %s\n", $_;
                $dbh->query('SELECT pgq.event_failed(?, ?, ?)', $batch_id, $event->{ev_id}, $_);
            };
        }

        $dbh->query('SELECT pgq.finish_batch(?)', $batch_id);
    }
    else {
        printf STDERR "INFO: Nothing to do\n";
        sleep(10);
    }
}
