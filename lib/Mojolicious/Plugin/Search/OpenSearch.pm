package Mojolicious::Plugin::Search::OpenSearch;
use Mojo::Base 'Mojolicious::Plugin';
use File::Basename 'dirname';
use File::Spec::Functions 'catdir';

# Todo: Support json!

our @OS_PARAM_DESC = qw/short_name description long_name
			tags contact developer attribution
			syndication_right language/;

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Check that search is loaded in advance

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Search-OpenSearch')) {
    $param = { %$config_param, %$param };
  };

  # Add templates
  push @{$mojo->renderer->paths}, catdir(dirname(__FILE__), 'OpenSearch','templates');

  my $helpers = $mojo->renderer->helpers;

  # Get endpoint plugin
  unless (exists $helpers->{endpoint}) {
    $mojo->plugin('Util::Endpoint');
  };

  # Missing information
  unless ($param->{short_name} && $param->{description}) {
    $mojo->log->warn('Missing "short_name" or "description"');
  };

  # Use moniker as short name
  $param->{short_name} //= $mojo->moniker;

  # Simple description
  $param->{description} //= 'OpenSearch';

  # Establish 'opensearch' shortcut
  $mojo->routes->add_shortcut(
    opensearch => sub {
      my $r = shift;
      my %osparam = @_;

      my $hit = delete $osparam{hit};

      if (!$hit || ref $hit ne 'CODE') {
	$mojo->log->error('No hit callback established');
	return;
      };

      my @osattr = qw/count startPage startIndex language/;

      my %hash;
      # Mandatory parameters
      foreach (qw/format searchTerms/) {
	$osparam{$_} //= $_;
	$hash{ $osparam{$_} } = '{' . $_ . '}';
      };

      # Optional parameters
      foreach (@osattr) {
	# qw/inputEncoding outputEncoding/
	$osparam{$_} //= $_ ;
	$hash{ $osparam{$_} } = '{' . $_ . '?}';
      };

      # Establish endpoint
      $r->endpoint(opensearch => { query => [ %hash ] });

      # Establish callback
      $r->any->to(
	cb => sub {
	  my $c = shift;

	  my $searchTerms = $c->param( $osparam{searchTerms} );

	  # No searchTerms defined
	  unless ($searchTerms) {
	    return $c->render_not_found(
	      text => 'The request is missing a search term',
	      status => '400' # Bad request
	    );
	  };

	  # Set opensearch stash values
	  foreach (@OS_PARAM_DESC) {
	    $c->stash('opensearch.' . $_ => $param->{$_}) if $param->{$_};
	  };

	  # Start creating query
	  $c->stash('search.searchTerms' => $searchTerms);

	  # Count, StartPage, startIndex, language
	  foreach (@osattr) {
	    my $key = $osparam{$_};
	    my $val = $c->param($key) or next;
	    if ($_ ne 'language') {

	      # check all numbers are numbers
	      next if $val !~ s/^\s*(\d+)\s*/$1/;
	    };
	    $c->stash('search.' . $key => $val);
	  };

	  # Set default format
	  $c->stash('format' => scalar($c->param('format')) // 'rss');

	  $c->render(
	    template => 'opensearch/results',
	    hit => $hit
	  );
	}
      );
    }
  );

  # Description file
  my $desc = delete $param->{file} || '/.well-known/opensearch.xml';

  $mojo->routes->get($desc)->to(
    cb => sub {
      my $c = shift;

      # Set opensearch stash values
      foreach (@OS_PARAM_DESC) {
	$c->stash('opensearch.' . $_ => $param->{$_}) if $param->{$_};
      };

      # Set content type
      $c->res->headers->content_type('application/opensearchdescription+xml');

      # TODO: Render this in advance
      return $c->render(
	template => 'opensearch/description',
	format   => 'xml'
      );
    })->name('opensearch-description');
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Search::OpenSearch - OpenSearch for Mojolicious


=head1 SYNOPSIS


  use Mojolicious::Lite;

  plugin Search => {};

  plugin 'Search::OpenSearch' => {
    short_name => 'My search',
    description => 'Search my site using OpenSearch'
  };

  get('/search/open')->opensearch(
    hit => sub {
      my ($c, $hit) = @_;
      return {
        title => $hit->{title},
        link => $hit->{url},
        snippet => $hit->{highlight}
      }
    }
  );


=head1 DESCRIPTION

L<Mojolicious::Plugin::Search::OpenSearch> is an L<OpenSearch|http://www.opensearch.org>
extension to L<Mojolicious::Plugin::Search>.

B<This is early software, please use it with care.>

=head1 METHODS

L<Mojolicious::Plugin::Search::OpenSearch> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.


=head2 register

Called when registering the plugin.
All parameters can be set either on registration or as part
of the configuration file with the key C<Search-OpenSearch>.

Accepts the parameters C<short_name>, C<description>, C<language>,
C<long_name>, C<developer>, C<contact>, C<adult_content>, C<attribution>,
and C<syndication_right>.
See the L<specification|http://www.opensearch.org/Specifications/OpenSearch/1.1#OpenSearch_description_document> for further information on these attributes.
Both C<short_name> and C<description> are mandatory.

Additionally supports the attribute C<file>, setting the path to the
description document. Defaults to C</.well-known/opensearch.xml>.


=head1 SHORTCUTS

=head2 opensearch

  get('/myopensearch')->opensearch(
    searchTerms => 'q',
    startPage => 'page',
    hit => sub {
      my ($c, $hit) = @_;
      return {
        title => $hit->{title},
        link => $hit->{url},
        snippet => $hit->{highlight}
      }
    }
  );

Defines the endpoint for C<rss> and C<atom> responses.
Accepts parameters to rewrite the name of the following
query parameters supported by OpenSearch: C<count>, C<startPage>,
C<startIndex>, C<language> and C<searchTerms>.
See the L<specification|http://www.opensearch.org/Specifications/OpenSearch/1.1#OpenSearch_URL_template_syntax> for further information on these attributes.

=over 2

=item B<hit>

In adition to the parameters mentioned above, the C<hit> parameter expects a
callback function, that is called for each hit.
Passed parameters is the controller object and the hit object.
Expects a hash reference with string values for C<title>, C<link> and C<snippet>
of the hit.

=back

Establishes an L<endpoint|Mojolicious::Plugin::Util::Endpoint> with
the name C<opensearch>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Search


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
