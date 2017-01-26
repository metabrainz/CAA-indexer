FROM ubuntu:14.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libanyevent-perl \
        libconfig-tiny-perl \
        libdbd-pg-perl \
        libdbix-simple-perl \
        libjson-any-perl \
        liblog-contextual-perl \
        libnet-amazon-s3-perl \
        libtry-tiny-perl \
        libwww-perl \
        libxml-xpath-perl \
        software-properties-common && \
    add-apt-repository ppa:metabrainz/musicbrainz-server && \
    apt-get update && \
    apt-get install -y --no-install-recommends libnet-rabbitfoot-perl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /caa-indexer

WORKDIR /caa-indexer

COPY ./ ./
COPY ./docker/local-configs/caa-indexer/config.ini ./

ENTRYPOINT ["perl", "-Ilib", "./caa-indexer"]
