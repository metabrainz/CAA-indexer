package CoverArtArchive::Indexer::Context;
use Config::Tiny;
use LWP::UserAgent;
use Moose;
use Net::Amazon::S3;

has s3 => (
    is => 'ro',
    required => 1,
    lazy => 1,
    builder => '_build_s3',
    clearer => '_clear_s3',
);

sub _build_s3 {
    my $self = shift;

    my $config = $self->config->{caa};

    my $s3 = Net::Amazon::S3->new(
        aws_access_key_id => $config->{public_key},
        aws_secret_access_key => $config->{private_key},
    );
    $s3->{_caa_config} = $config;
    $s3;
}

has lwp => (
    is => 'ro',
    required => 1,
    lazy => 1,
    default => sub { LWP::UserAgent->new },
);

has config => (
    is => 'ro',
    required => 1,
    lazy => 1,
    builder => '_build_config',
    clearer => 'reload_config',
);

my $DEFAULT_UPLOAD_URL = '//{bucket}.s3.us.archive.org{file}';

sub _build_config {
    my $self = shift;

    # Clear other attributes which depend on config values.
    $self->_clear_s3;

    my $opts_config = $self->opts_config;
    my $config = Config::Tiny->read($opts_config->{config});

    $config->{caa}{upload_url} //= $DEFAULT_UPLOAD_URL;

    # Override settings from the config file with those specified on the
    # command line.
    for my $key (keys %{$opts_config}) {
        my $section = $opts_config->{$key};
        if (ref($section) eq 'HASH') {
            $config->{$key}{$_} = $section->{$_} for keys %{$section};
        }
    }

    $config;
}

has opts_config => (
    is => 'ro',
    required => 1,
    default => sub { {} },
);

__PACKAGE__->meta->make_immutable;
1;
