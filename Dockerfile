FROM metabrainz/consul-template-base

ARG BUILD_DEPS=" \
    build-essential \
    libexpat1-dev \
    libxml2-dev \
    postgresql-server-dev-9.5"

ARG RUN_DEPS=" \
    libexpat1 \
    libpq5 \
    libxml2 \
    perl \
    sudo"

RUN useradd --create-home --shell /bin/bash caa

ARG CAA_ROOT=/home/caa/CAA-indexer
WORKDIR $CAA_ROOT
RUN chown caa:caa $CAA_ROOT

ENV PERL_CARTON_PATH /home/caa/carton-local
ENV PERL_CPANM_OPT --notest --no-interactive

COPY cpanfile cpanfile.snapshot ./

RUN apt-get update && \
    apt-get install --no-install-suggests --no-install-recommends -y \
        $BUILD_DEPS \
        $RUN_DEPS && \
    rm -rf /var/lib/apt/lists/* && \
    wget -q -O - https://cpanmin.us | perl - App::cpanminus && \
    cpanm Carton && \
    mkdir -p $PERL_CARTON_PATH && \
    chown caa:caa $PERL_CARTON_PATH && \
    sudo -E -H -u caa carton install --deployment && \
    apt-get purge --auto-remove -y $BUILD_DEPS

COPY caa-indexer docker/config.ini.ctmpl ./
COPY lib/ lib/
COPY t/ t/

RUN chown -R caa:caa $CAA_ROOT

COPY docker/caa-indexer.service /etc/service/caa-indexer/run
COPY docker/consul-template.conf /etc/
