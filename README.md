# caa-indexer

A daemon that watches the 'CoverArtIndex' queue for events that indicate it
should update the index file at the Internet Archive.

## Installation

You will need:

* A MusicBrainz database. See the `INSTALL.md` document of the `musicbrainz-server`
  project for more details.

* pgq installed:

  1. Grab skytools from http://skytools.projects.postgresql.org/ and install it
     with the normal `configure`, `make`, `make install` trio. If you are
     running Ubuntu, simply install the `skytools` package
     (`sudo apt-get install skytools`).
  2. Create a musicbrainz.ini file somewhere. See musicbrainz.ini.example for
     how this could look.
  3. Run `pgqadm.py /path/to/musicbrainz.ini install` to install PGQ into the
     database.
  4. Run `pgqadm.py /path/to/musicbrainz.ini ticker -d` to start the ticker
  5. Run the `install.sql` file in this project against your MusicBrainz database.
  6. Install dependencies with `carton install`
  7. Copy `config.ini.example` to `config.ini` and edit appropriately.
  7. Run `caa-indexer` as `carton exec -Ilib -- ./caa-indexer`. You will need to
     provide the public and private key, via the `--public=` and `--private=`
     options, respectively, or via the aforementioned `config.ini`.
     Run with `--help` for options.
