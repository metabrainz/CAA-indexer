# caa-indexer

A daemon that watches the 'CoverArtIndex' queue for events that indicate it
should update the index file at the Internet Archive.

## Installation

You will need:

- A MusicBrainz database. See the `INSTALL.md` document of the `musicbrainz-server`
  project for more details.
- RabbitMQ

This roughly corresponds to:

  1. Install RabbitMQ:

       sudo apt-get install rabbitmq

  2. Install dependencies:

       carton install

  7. Copy `config.ini.example` to `config.ini` and edit appropriately.
  7. Run `caa-indexer`:

       carton exec -Ilib -- ./caa-indexer

     You will need to provide the public and private key, via the `--public=`
     and `--private=` options, respectively, or via the aforementioned
     `config.ini`.  Run with `--help` for options.
