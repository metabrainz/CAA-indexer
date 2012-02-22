# caa-indexer

A daemon that watches the 'CoverArtIndex' queue for events that indicate it
should update the index file at the Internet Archive.

## Installation

You will need:

* A MusicBrainz database. See the `INSTALL` document of the `musicbrainz-server`
  project for more details.

* pgq installed:

  1. Grab skytools from http://skytools.projects.postgresql.org/ and install it
     with the normal `configure`, `make`, `make install` trio.
  2. Create a musicbrainz.ini file somewhere. See musicbrainz.ini.example for
     how this could look.
  3. Run `pgq /path/to/musicbrainz.ini ticker -d` to start the ticker
  4. Run the `install.sql` file in this project against your MusicBrainz database.
  5. Run `caa-indexer`. Run with `--help` for options.
