package CoverArtArchive::IAS3Request;
use Moose::Role;

use HTTP::Request;

around 'http_request' => sub {
    my $orig     = shift;
    my $self     = shift;
    my $method   = $self->method;
    my $path     = $self->path;
    my $headers  = $self->headers;
    my $content  = $self->content;
    my $metadata = $self->metadata;

    my $http_headers = $self->_merge_meta( $headers, $metadata );

    $self->_add_auth_header( $http_headers, $method, $path )
        unless exists $headers->{Authorization};
    my $protocol = $self->s3->secure ? 'https' : 'http';
    $path =~ m{^([^/?]+)(.*)};
    my $uri = "$protocol://$1.s3.us.archive.org$2";

    my $request
        = HTTP::Request->new( $method, $uri, $http_headers, $content );

    return $request;
};

1;
