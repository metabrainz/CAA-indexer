include(`config.all.m4')dnl
changequote(<,>)dnl
#!/bin/bash

RABBITMQ_PID_FILE=/var/run/rabbitmq.pid rabbitmq-server &
rabbitmqctl wait /var/run/rabbitmq.pid

rabbitmqctl add_user RABBITMQ_USERNAME ifelse(RABBITMQ_PASSWORD, <>, <''>, <RABBITMQ_PASSWORD>)
rabbitmqctl add_vhost RABBITMQ_VHOST
rabbitmqctl set_permissions -p RABBITMQ_VHOST RABBITMQ_USERNAME '.*' '.*' '.*'

rabbitmqctl stop /var/run/rabbitmq.pid
exec rabbitmq-server
