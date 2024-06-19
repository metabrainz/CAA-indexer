**:warning: Note: This repository has been replaced with [artwork-indexer](https://github.com/metabrainz/artwork-indexer) since March 28, 2024.**

----

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

  2. Set up local::lib

         sudo apt-get install liblocal-lib-perl libmodule-install-perl
         eval $(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib)
         cpan App::cpanminus
     
         # The above will allow you install perl modules to ~/perl5.
         # Copy the "eval ..." line to your ~/.bashrc or equivalent
         # to ensure perl programs will be able to find these modules
         # again when you start a new shell.

  4. Install perl dependencies:

         sudo apt-get install perl perl-modules libanyevent-perl    \
           libconfig-tiny-perl libdbd-pgsql libdbix-simple-perl     \
           libjson-any-perl liblog-contextual-perl libwww-perl      \
           libnet-amazon-s3-perl libtry-tiny-perl libxml-xpath-perl
     
         cpanm --installdeps .

  6. Copy `config.ini.example` to `config.ini` and edit appropriately.

  7. Run `caa-indexer`:

         ./caa-indexer

     You will need to provide the public and private key, via the `--public=`
     and `--private=` options, respectively, or via the aforementioned
     `config.ini`.  Run with `--help` for options.
