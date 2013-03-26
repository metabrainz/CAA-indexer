package CoverArtArchive::Indexer;
use Moose;

use AnyEvent;
use CoverArtArchive::Indexer::EventHandler::Delete;
use CoverArtArchive::Indexer::EventHandler::Index;
use CoverArtArchive::Indexer::EventHandler::Move;
use Log::Contextual qw( :log );
use Try::Tiny;

with 'CoverArtArchive::Indexer::UseContext';

has event_handlers => (
    lazy => 1,
    default => sub {
        my $self = shift;
        return [
            map { $_->new( c => $self->c ) }
              qw(
                CoverArtArchive::Indexer::EventHandler::Delete
                CoverArtArchive::Indexer::EventHandler::Index
                CoverArtArchive::Indexer::EventHandler::Move
              )
        ]
    },
    traits => [ 'Array' ],
    handles => {
        event_handlers => 'elements'
    }
);

sub run {
    my $self = shift;

    # The main exchange for the CAA
    $self->rabbitmq->declare_exchange( exchange => 'cover-art-archive', type => 'direct' );

    # Messages arriving here will be delayed for 4-hours
    $self->rabbitmq->declare_queue(
        queue => 'cover-art-archive.retry',
        arguments => {
            'x-message-ttl' => 4 * 60 * 60 * 1000, # 4 hours
            'x-dead-letter-exchange' => 'cover-art-archive'
        }
    );

    # Declare a fanout exchange to enqueue retries.
    # Fanout allows us to preserve the routing key when we dead-letter back to the cover-art-archive exchange
    $self->rabbitmq->declare_exchange( exchange => 'cover-art-archive.retry', type => 'fanout' );
    $self->rabbitmq->bind_queue( exchange => 'cover-art-archive.retry', queue => 'cover-art-archive.retry' );

    # Messages sent here need manual intervention
    $self->rabbitmq->declare_exchange( exchange => 'cover-art-archive.failed', type => 'fanout' );
    $self->rabbitmq->declare_queue( queue => 'cover-art-archive.failed' );
    $self->rabbitmq->bind_queue( queue => 'cover-art-archive.failed', exchange => 'cover-art-archive.failed' );

    for my $handler ($self->event_handlers) {
        my $queue = $handler->queue;

        $self->rabbitmq->declare_queue(
            queue => "cover-art-archive.$queue", durable => 1
        );

        $self->rabbitmq->bind_queue(
            queue => "cover-art-archive.$queue",
            exchange => 'cover-art-archive',
            routing_key => $queue
        );

        $self->rabbitmq->consume(
            queue => 'cover-art-archive.' . $handler->queue,
            no_ack => 0,
            on_consume => sub {
                my $delivery = shift;
                my $tag = $delivery->{deliver}{method_frame}{delivery_tag};
                my $boy = $delivery->{body}{payload};

                try {
                    $handler->handle($body);
                }
                catch {
                    log_error { sprintf "Error running event handler: %s", $_ };

                    my $retries_remaining = ($delivery->{header}{headers}{'mb-retries'} // 4);
                    $self->rabbitmq->publish(
                        routing_key => $delivery->{deliver}{method_frame}{routing_key},

                        exchange => $retries_remaining > 0
                            ? 'cover-art-archive.retry'
                            : 'cover-art-archive.failed',

                        body => $body,
                        header => {
                            headers => {
                                'mb-retries' => $attempt - 1,
                                'mb-exceptions' => [
                                    @{ $delivery->{header}{headers}{'mb-exceptions'} // [] },
                                    $_
                                ]
                            }
                        }
                    );
                };

                $self->rabbitmq->ack( delivery_tag => $tag );
            }
        );
    }

    # Wait forever
    AnyEvent->condvar->recv;
}

1;
