# Cover Art Archive Indexer Architecture

The CAA-indexer project uses RabbitMQ in style reminiscent of the worker
pattern. There are five queues in this project:

- `cover-art-archive.index`, `cover-art-archive.delete` and
  `cover-art-archive.move` receive job requests for indexing, deleting and
  moving CAA artwork, respectively.
- `cover-art-archive.retry` stores events that will be retried in 4 hours.
- `cover-art-archive.failed` stores events that could not be processed, even
  after retries.

To route to these queues, there are three exchanges:

- `cover-art-archive` is a direct exchange, which is bound to the `.index`,
  `.move` and `.delete` queues.
- `cover-art-archive.retry` is a fanout exchange which routes messages to the
  `.retry` queue. By using a fanout exchange, we can retain the routing keys for
  the messages.
- `cover-art-archive.failed` is a fanout exchange, which again just routes to a
  single queue (`.failed`) and retains the routing key.

## Automatic Retries

To achieve automatic retries, we take advantage of dead letter exchanges and a
decreasing retry series. Here's how it works.

When a message is failed, we first inspect the `mb-retries` header. This header
should contain a natural number, which indicates the amount of retries
*remaining*. If this header isn't present, it will be set to a default value -
the default amount of retries for a message. If the value of this header is > 0,
then the message has retries available and will be sent to the
`cover-art-archive.retry` exchange *with the retry count decremented*, otherwise
it is sent to the `cover-art-archive.failed` exchange.

The `cover-art-archive.retry` exchange will route this message onto the
`cover-art-archive.retry` queue, which generally has no consumers. However, this
queue is configured with a [TTL](https://www.rabbitmq.com/ttl.html) of 4 hours,
upon which messages will be expired. The queue is also configured to [dead
letter](https://www.rabbitmq.com/dlx.html) to the `cover-art-archive` exchange,
so the net effect is that after 4 hours, messages will be sent back to the
`cover-art-archive` for another attempt.

The `cover-art-archive.failed` exchange doesn't really do much, other than
archive messages. This queue will need human monitoring and intervention to see
if there really is an underlying problem.
