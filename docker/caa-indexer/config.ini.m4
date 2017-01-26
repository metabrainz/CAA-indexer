include(`config.all.m4')dnl
[database]
host = POSTGRES_HOST
port = POSTGRES_PORT
user = POSTGRES_USERNAME
database = POSTGRES_DATABASE
ifelse(ifdef(`POSTGRES_PASSWORD', `POSTGRES_PASSWORD'), `', `dnl', `password = POSTGRES_PASSWORD')

[rabbitmq]
host = RABBITMQ_HOST
port = RABBITMQ_PORT
user = RABBITMQ_USERNAME
pass = RABBITMQ_PASSWORD
vhost = RABBITMQ_VHOST

[caa]
public_key = CAA_PUBLIC_KEY
private_key = CAA_PRIVATE_KEY
