package Mojolicious::Plugin::Search;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::Search::Index;
use Scalar::Util 'looks_like_number';
use Mojo::Util qw/camelize/;
use Mojo::ByteStream 'b';

our $VERSION = '0.04';

# TODO: Improve the documentation by using similar
#       attribute style as in M::P::S::Lucy
# TODO: Check for failing engines (e.g. methods missing)

# Maximum number of items per page
has items_per_page => 25;
has engine => __PACKAGE__ . '::Lucy';


# Register plugin
sub register {
  my ($plugin, $app, $param) = @_;
  $param ||= {};

  # Load parameter from Config file
  if (my $config_param = $app->config('Search')) {
    $param = { %$param, %$config_param };
  };

  # Set engine
  $plugin->engine(delete $param->{engine})
    if $param->{engine};

  # Set items per page if given
  $plugin->items_per_page(delete $param->{items_per_page})
    if $param->{items_per_page};

  # Get specific search engine
  my $engine = camelize($plugin->engine);

  # Engine is relative
  $engine = __PACKAGE__ . '::' . $engine if index($engine, '::') < 0;

  # Load and register the engine
  my $e = $app->plugins->load_plugin($engine) or return;
  $e->register($app, __PACKAGE__ . '::Index', $param);

  # No search method in plugin
  unless ($e->can('search')) {
    $app->log->error(qq!$engine expects a 'search' method!);
    return;
  };

  # Establishes 'search' helper
  $app->helper(
    search => sub {
      my $c = shift;

      # Return searcher object
      if (@_ == 0) {

	# 'Index' object may already be initialized
	return $c->stash->{'search._index'} //= _index(
	  controller => $c,
	  engine => $e
	);
      };

      # Get new 'Index' object
      my $index = _index(
	controller => $c,
	engine => $e
      );
      $c->stash->{'search._index'} = $index;

      # Get callback for templates
      my $cb = pop if (@_ % 2) != 0 && ref $_[-1] && ref $_[-1] eq 'CODE';

      # Get parameters for search
      my %param = @_;

      # Set query
      $index->query(delete $param{query} // $c->stash('search.query'));

      # No query defined
      return unless $index->query;

      # Set count
      if ($param{count} &&
	    looks_like_number($param{count}) &&
	      $param{count} <= $plugin->items_per_page ) {
	$index->items_per_page(delete $param{count});
      }
      # already set by stash - or use plugin param
      else {
	$index->items_per_page(
	  $c->stash('search.count') // $plugin->items_per_page
	);
      };

      # Set start page based on param
      if ($param{start_page} && looks_like_number($param{start_page})) {
	$index->start_page(delete $param{start_page});
      }
      # already set by stash
      elsif ($c->stash('search.start_page')) {
	$index->start_page($c->stash('search.start_page'));
      };

      # Non-blocking call (at least possible for engines)
      if ($param{cb} || $param{template}) {

	# Prevent automatic rendering
	$c->render_later;

	# Search non-blocking with callback
	if (my $cb = delete $param{cb}) {
	  $e->search($index, @_, $cb);
	}

	# Search non-blocking with template information
	elsif (my $template = delete $param{template}) {
	  $e->search(
	    $index, @_, sub {
	      $c->render(template => $template);
	    });
	};

	return 1;
      };

      # Blocking call
      $e->search($index, @_);

      # Return object in case it's not called in a template
      return $index unless $cb;

      # Template callback
      my $value = $cb->($c);

      # Remove hits from stash (maybe not necessary)
      foreach (qw/results total_results _index/) {
	delete $c->stash->{"search.$_"};
      };

      # Return value
      return $value;
    }
  );


  # Establish 'search_results' taghelper
  $app->helper(
    search_results => sub {
      my $c = shift;

      # Get 'Index' object from stash
      my $index = $c->stash('search._index') or return;

      # This is a tag helper for templates
      my $cb = shift;
      if (!ref $cb || !(ref $cb eq 'CODE')) {
	$c->app->log->error('search_results expects a code block');
	return '';
      };

      # Iterate over results
      my $string = $index->results->map(
	sub {
	  # Call hit callback
	  $c->stash('search.hit' => $_);
	  local $_ = $_[0];
	  return $cb->($_);
	})->join;

      # Remove hit from stash
      delete $c->stash->{'search.hit'};
      return b($string);
    }
  );


  # Run init on engine (that's not really recommended)
  if ($param->{on_init} &&
	ref $param->{on_init} &&
	  ref $param->{on_init} eq 'CODE') {
    $param->{on_init}->(
      _index(
	controller => $app->build_controller,
	engine => $e
      )
    );
  };
};


# Return 'Index' object
sub _index {
  Mojolicious::Plugin::Search::Index->new(@_);
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Search - Search Engines for Mojolicious


=head1 SYNOPSIS

  use Mojolicious::Lite;

  # Load plugin in Mojolicious
  plugin Search => {
    items_per_page => 25,

    # Engine specific configuration:
    engine => 'Lucy',
    schema => {
      content => {
        type => 'fulltext',
        highlightable => 1,
        stored => 1
      },
      title => {
        type => 'fulltext',
        highlightable => 1,
        stored => 1
      },
      url => {
        type => 'string',
        indexed => 0
      }
    },

    # Initialize index with some documents
    on_init => sub {
      shift->add(
        {
          title => 'My first Ballon',
	  content => 'Please find me!',
          url => '/page1'
        },
        {
          title => 'My second Ballon',
	  content => 'Thanks for searching',
	  url => '/page2'
        }
      );
    }
  };

  get '/' => sub {
    shift->render('index');
  };

  app->start;

  __DATA__

  @@ layouts/default.html.ep
  <!DOCTYPE html>
  <html>
    <head><title><%= title %></title></head>
    <body>
      <h1><%= title %></h1>
  %= content
    </body>
  </html>

  @@ index.html.ep
  % layout 'default', title => 'Search';

  %# Set search form
  %= form_for url_for, begin
  %=   search_field 'q'
  % end

  %= search query => param('q'), begin
  % title 'Search for ' . search->query;

  <p>Found <%= search->total_results %> matches</p>
  <ul>
  %=  search_results begin
    <li>
      <h2><%= link_to $_->{title}, $_->{url} %></h2>
      <p><%= $_->{content} %></p>
    </li>
  %   end
  </ul>
  % end


=head1 DESCRIPTION

L<Mojolicious::Plugin::Search> is a base plugin to add
search capabilities to Mojolicious.

B<This is early software, please use it with care! Things may change until it is on CPAN!>


=head1 METHODS

L<Mojolicious::Plugin::Search> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.


=head2 register

Called when registering the plugin.
All parameters can be set either on registration or as part
of the configuration file with the key C<Search>
(with the configuration file having the higher precedence).


Accepts the following parameters:

=over 2

=item B<items_per_page>

Set the maximum number of hits shown per page.


=item B<engine>

A L<Mojolicious::Plugin::Search> engine.
Defaults to
L<Lucy|Mojolicious::Plugin::Search::Lucy>. See
L<Mojolicious::Plugin::Search::Lucy> for further information.

=back

All further parameters are passed to the chosen engine.


=head1 HELPERS

=head2 search

  # In controller (blocking)
  my $result = $c->search(q => 'test');
  # print $result->total_results;
  # print $result->hit(2)->title;

  # In controller (non-blocking)
  $c->search(
    query => 'name',
    start_page => 4,
    count => 25,
    cb => sub {
      my $index = shift;
      $c->render(text => 'Found ' . $index->total_results . ' matches!');
    }
  );

  # In Templates (blocking)
  %= search query => 'test', begin
  %# ...
  % end

Initializes a search.

The parameter C<query> defines the query terms,
C<start_page> defines the numerical starting page of the search,
C<count> defines the number of results that should be shown per page.
If C<count> is greater than C<items_per_page>, it will be limited to that.

The parameter C<cb> can be used to pass a callback method to be evaluated
(e.g., in case of a non-blocking search). The parameter C<template> may define
a template to render after a search (also for non-blocking searches).

C<query> and C<start_page> may also be defined in advanced
using the L<Mojolicious::Controller/stash|stash>, if prefixed with C<search.>.
C<count> may also be set as C<search.items_per_page>, overriding
the plugin default value limit.

In addition to theses parameters, L</search|search> accepts arbitrary engine
specific parameters.

When called without C<cb> or C<template>, the method returns a
L<Mojolicious::Plugin::Search::Index|Index object>,
representing search parameters and probably results.
When called with C<cb> the callback is executed with the
L<Mojolicious::Plugin::Search::Index|Index object> as the first parameter.

In templates, L</search|search> can be used either as a tag helper, expecting a
nested L</search_results|search_results> block for displaying the results
(This usage is, however, not recommended for long-term searches!),
or as a proxy object for accessing L<Mojolicious::Plugin::Search::Index|Index object>.

  %# In templates
  <p>Found <%= search->total_results %> matches</p>
  <p>Show page <%= search->start_page %>/<%= search->total_pages %></p>


=head2 search_results

  %= search begin
  %=  search_results begin
    <p><%= $_->{title} %></p>
    <p><%= $_->{content} %></p>
  %   end
  % end

Iterates over all hits for a certain query, contains a hit object
in C<$_> and the stash value C<search.hit>.
The concrete realization of the hit is engine specific.


=head1 ENGINES

L<Mojolicious::Plugin::Search> is bundled with an
L<Apache Lucy|Mojolicious::Plugin::Search::Lucy> engine.


=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Lucy>,
L<Mojolicious::Plugin::Util::Endpoint>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Search


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
