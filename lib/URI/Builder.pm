package URI::Builder;

use strict;
use warnings;

=head1 NAME

URI::Builder

=cut

use URI;
use Scalar::Util qw( blessed );
use Carp qw( confess );

# Utility functions
sub flatten {
    return map {
        ref $_ eq 'ARRAY' ? flatten(@$_)
      : ref $_ eq 'HASH'  ? flatten_hash($_)
      : $_
    } @_ = @_;
}

sub flatten_hash {
    my $hash = shift;

    return map {
        my ($k, $v) = ($_, $hash->{$_});
        map { $k => $_ } flatten $v
    } keys %$hash;
}

use namespace::clean;

use overload ('""' => \&as_string, fallback => 1);

my (@uri_fields, %listish, @fields);

BEGIN {
    # Fields that correspond to methods in URI
    @uri_fields = qw(
        scheme
        userinfo
        host
        port
        path_segments
        query_form
        query_keywords
        fragment
    );

    # Fields that contain lists of values
    %listish = map { $_ => 1 } qw(
        path_segments
        query_form
        query_keywords
    );

    # All fields
    @fields = ( @uri_fields, qw( query_separator ));

    # Generate accessors for all fields:
    for my $field (@fields) {
        my $glob = do { no strict 'refs'; \*$field };

        *$glob = $listish{$field} ? sub {
            my $self = shift;
            my @old = @{ $self->{$field} || []};
            $self->{$field} = [ flatten @_ ] if @_;
            return @old;
        }
        : sub {
            my $self = shift;
            my $old = $self->{$field};
            $self->{$field} = shift if @_;
            return $old;
        };
    }
}

sub clone {
    my $self = shift;

    my %clone = %$self;
    for my $list ( keys %listish ) {
        $clone{$list} &&= [ @{ $clone{$list} || [] } ];
    }

    return $self->new(%clone);
}

sub new {
    my $class = shift;
    my %opts = @_ == 1 && ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;

    $opts{query_separator} ||= ';';

    if (my $uri = $opts{uri}) {
        $uri = URI->new($uri, 'http') unless blessed $uri;

        for my $field (@uri_fields) {
            $opts{$field} ||=
              $listish{$field} ? [ $uri->$field ] : $uri->$field;
        }
    }

    $_ = [ flatten $_ ] for grep defined && !ref, @opts{ keys %listish };

    # Still no scheme? Default to http
    # $opts{scheme} ||= 'http';

    my $self = bless { map { $_ => $opts{$_} } @fields }, $class;

    delete @opts{@fields};

    for my $field (keys %opts) {
        if (my $method = $self->can($field)) {
            $method->($self, flatten delete $opts{$field});
        }
    }

    if (my @invalid = sort keys %opts) {
        die "Unrecognised fields in constructor: ", join ', ', @invalid;
    }

    return $self;
}

sub uri {
    my $self = shift;

    return URI->new($self->as_string);
}

sub as_string {
    my $self = shift;

    my @parts;

    if (my $authority = $self->authority) {
        if (my $scheme = $self->scheme) {
            push @parts, "$scheme:";
        }

        $authority =~ s/:@{[ $self->default_port ]}\z//;

        push @parts, "//$authority";
    }

    if (my $path = $self->path) {
        $path =~ s{^(?!/)}{/} if @parts;
        push @parts, $path;
    }

    if (my $query = $self->query) {
        push @parts, "?$query";
    }

    if (my $fragment = $self->fragment) {
        push @parts, "#$fragment";
    }

    return join('', @parts);
}

my %port;
sub default_port {
    my $self = shift;
    my $scheme = $self->scheme || 'http';
    return $port{$scheme} ||= URI::implementor($scheme)->default_port;
}

my %secure;
sub secure {
    my $self = shift;
    my $scheme = $self->scheme || 'http';
    return $secure{$scheme} ||= URI::implementor($scheme)->secure;
}

sub authority {
    my $self = shift;
    my ($user, $host) = ($self->userinfo, $self->host_port);

    return $host ? $user ? "$user\@$host" : $host : '';
}

sub host_port {
    my $self = shift;
    my ($host, $port) = ($self->host, $self->port);

    return $host ? $port ? "$host:$port" : $host : '';
}

sub as_iri {
    confess "TODO";
}

sub ihost {
    confess "TODO";
}

sub abs {
    my ($self, $base) = @_;

    confess "TODO";
}

sub rel {
    my ($self, $base) = @_;

    confess "TODO";
}

sub path {
    my $self = shift;

    my $old = join '/', $self->path_segments;

    if (@_) {
        my @segments = split '/', shift, -1;
        $self->path_segments(@segments);
    }

    return $old;
}

sub query {
    my ($self, $query) = @_;

    my @new;
    if ($query) {
        # Parse the new query string using a URI object
        @new = URI->new("?$query", $self->scheme)->query_form;
    }

    unless (defined wantarray) {
        # void context, don't bother building the query string
        $self->query_form(@new);
        return;
    }

    my $old;
    if (my @form = $self->query_form) {
        $old = join(
            $self->query_separator,
            map { $_ % 2 ? () : "$form[$_]=$form[$_ + 1]" } 0 .. $#form
        );
    }
    else {
        $old = join '+', $self->query_keywords;
    }

    $self->query_form(@new);

    return $old;
}

sub path_query {
    my $self = shift;
    my ($path, $query) = ($self->path, $self->query);

    return $path . ($query ? "?$query" : '');
}

sub query_param {
    my ($self, $key, @values) = @_;
    my @form = $self->query_form;

    if ($key) {
        my @indices = grep $_ % 2 == 0 && $form[$_] eq $key, 0 .. $#form;
        my @old_values = @form[ map $_ + 1, @indices ];

        if (@values) {
            @values = flatten @values;
            splice @form, pop @indices, 2 while @indices > @values;

            my $last_index = @indices ? $indices[-1] + 2 : @form;

            while (@values && @indices) {
                splice @form, shift @indices, 2, $key, shift @values;
            }

            if (@values) {
                splice @form, $last_index, 0, map { $key => $_ } @values;
            }

            $self->query_form(@form);
        }

        return @old_values;
    }
    else {
        my %seen;
        return grep !$seen{$_}++, map $form[$_], grep $_ % 2 == 0, 0 .. $#form;
    }
}

sub query_param_append {
    my ($self, $key, @values) = @_;

    $self->query_form($self->query_form, map { $key => $_ } flatten @values);

    return;
}

sub query_param_delete {
    my ($self, $key) = @_;

    return $self->query_param($key, []);
}

sub query_form_hash {
    my $self = shift;
    my @new;

    if (my %form = @_ == 1 && ref $_[0] eq 'HASH' ? %{ $_[0] } : @_) {
        @new = flatten_hash(\%form);
    }

    unless (defined wantarray) {
        # void context, don't bother building the hash
        $self->query_form(@new);
        return;
    }

    my %form = map {
        my @values = $self->query_param($_);
        ( $_ => @values == 1 ? $values[0] : \@values );
    } $self->query_param;
    
    $self->query_form(@new) if @new;

    return \%form;
}

1;

__END__

canonical
default_port
via URI::_server: _host_escape
via URI::_server: _port
via URI::_server: _uric_escape
via URI::_server: as_iri
via URI::_server: host
via URI::_server: host_port
via URI::_server: ihost
via URI::_server: port
via URI::_server: uri_unescape
via URI::_server: userinfo
via URI::_server -> URI::_generic: _check_path
via URI::_server -> URI::_generic: _no_scheme_ok
via URI::_server -> URI::_generic: _split_segment
via URI::_server -> URI::_generic: abs
via URI::_server -> URI::_generic: authority
via URI::_server -> URI::_generic: path
via URI::_server -> URI::_generic: path_query
via URI::_server -> URI::_generic: path_segments
via URI::_server -> URI::_generic: rel
via URI::_server -> URI::_generic -> URI: (!=
via URI::_server -> URI::_generic -> URI: (""
via URI::_server -> URI::_generic -> URI: ()
via URI::_server -> URI::_generic -> URI: (==
via URI::_server -> URI::_generic -> URI: STORABLE_freeze
via URI::_server -> URI::_generic -> URI: STORABLE_thaw
via URI::_server -> URI::_generic -> URI: _init
via URI::_server -> URI::_generic -> URI: _init_implementor
via URI::_server -> URI::_generic -> URI: _obj_eq
via URI::_server -> URI::_generic -> URI: _scheme
via URI::_server -> URI::_generic -> URI: as_string
via URI::_server -> URI::_generic -> URI: clone
via URI::_server -> URI::_generic -> URI: eq
via URI::_server -> URI::_generic -> URI: fragment
via URI::_server -> URI::_generic -> URI: implementor
via URI::_server -> URI::_generic -> URI: new
via URI::_server -> URI::_generic -> URI: new_abs
via URI::_server -> URI::_generic -> URI: opaque
via URI::_server -> URI::_generic -> URI: scheme
via URI::_server -> URI::_generic -> URI: secure
via URI::_server -> URI::_generic -> URI::_query: equery
via URI::_server -> URI::_generic -> URI::_query: query
via URI::_server -> URI::_generic -> URI::_query: query_form
via URI::_server -> URI::_generic -> URI::_query: query_keywords

