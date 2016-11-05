package CoverArtArchive::Indexer;
use Moose;

use AnyEvent;
use AnyEvent::RabbitMQ;
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

sub on_open_channel {
    my ($self, $cv, $channel) = @_;

    # The main exchange for the CAA
    $channel->declare_exchange(
        exchange => 'cover-art-archive',
        type => 'direct',
        durable => 1,
        on_failure => $cv,
    );

    # Messages arriving here will be delayed for 4-hours
    $channel->declare_queue(
        queue => 'cover-art-archive.retry',
        durable => 1,
        arguments => {
            'x-message-ttl' => 4 * 60 * 60 * 1000, # 4 hours
            'x-dead-letter-exchange' => 'cover-art-archive'
        },
        on_failure => $cv,
    );

    # Declare a fanout exchange to enqueue retries.
    # Fanout allows us to preserve the routing key when we dead-letter back to the cover-art-archive exchange
    $channel->declare_exchange(
        exchange => 'cover-art-archive.retry',
        type => 'fanout',
        durable => 1,
        on_failure => $cv,
    );

    $channel->bind_queue(
        exchange => 'cover-art-archive.retry',
        queue => 'cover-art-archive.retry',
    );

    # Messages sent here need manual intervention
    $channel->declare_exchange(
        exchange => 'cover-art-archive.failed',
        type => 'fanout',
        durable => 1,
        on_failure => $cv,
    );

    $channel->declare_queue(
        queue => 'cover-art-archive.failed',
        durable => 1,
        on_failure => $cv,
    );

    $channel->bind_queue(
        queue => 'cover-art-archive.failed',
        exchange => 'cover-art-archive.failed',
    );

    for my $handler ($self->event_handlers) {
        my $queue = $handler->queue;

        $channel->declare_queue(
            queue => "cover-art-archive.$queue",
            durable => 1,
            on_failure => $cv,
        );

        $channel->bind_queue(
            queue => "cover-art-archive.$queue",
            exchange => 'cover-art-archive',
            routing_key => $queue,
        );

        $channel->consume(
            queue => 'cover-art-archive.' . $handler->queue,
            no_ack => 0,
            on_consume => sub {
                my $delivery = shift;
                my $tag = $delivery->{deliver}{method_frame}{delivery_tag};
                my $body = $delivery->{body}{payload};

                try {
                    $handler->handle($body);
                }
                catch {
                    log_error { sprintf "Error running event handler: %s", $_ };

                    my $retries_remaining = ($delivery->{header}{headers}{'mb-retries'} // 4);
                    $channel->publish(
                        routing_key => $delivery->{deliver}{method_frame}{routing_key},

                        exchange => $retries_remaining > 0
                            ? 'cover-art-archive.retry'
                            : 'cover-art-archive.failed',

                        body => $body,
                        header => {
                            headers => {
                                'mb-retries' => $retries_remaining - 1,
                                'mb-exceptions' => [
                                    @{ $delivery->{header}{headers}{'mb-exceptions'} // [] },
                                    $_
                                ]
                            }
                        }
                    );
                };

                $channel->ack( delivery_tag => $tag );
            }
        );
    }
}

sub run {
    my $self = shift;

    my $cv = AnyEvent->condvar;

    my $ar = AnyEvent::RabbitMQ->new->load_xml_spec()->connect(
        %{ $self->config->{rabbitmq} },

        on_success => sub {
            my $ar = shift;

            $ar->open_channel(
                on_success => sub {
                    $self->on_open_channel($cv, shift);
                },
                on_failure => $cv,
            );
        },
    );

    # Wait forever
    $cv->recv;
}

1;
