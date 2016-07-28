include(`config.all.m4')dnl
version: '2'

services:
  caa-indexer:
    build:
      context: ../
      dockerfile: docker/caa-indexer/Dockerfile
    external_links:
      - musicbrainzserver_postgres-master_1:POSTGRES_HOST
    links:
      - rabbitmq:RABBITMQ_HOST
    volumes:
      - ../:/caa-indexer

  rabbitmq:
    build:
      context: ../
      dockerfile: docker/rabbitmq/Dockerfile
    expose:
      - "RABBITMQ_PORT"
