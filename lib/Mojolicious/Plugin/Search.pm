package Mojolicious::Plugin::Search;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/camelize/;
use Mojo::ByteStream 'b';

our $VERSION = '0.01';

has 'items_per_page' => 25;

# Register the plugin
sub register {
  my ($plugin, $mojo, $param) = @_;
  $param ||= {};

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Search')) {
    $param = { %$config_param, %$param };
  };

  # Get specific search engine
  my $engine = camelize(delete $param->{engine} // __PACKAGE__ . '::Lucy');

  $plugin->items_per_page($param->{items_per_page}) if $param->{items_per_page};

  # Engine is relative
  if (index($engine, '::') < 0) {
    $engine = __PACKAGE__ . '::' . $engine;
  };

  # Load and register
  my $engine_plugin = $mojo->plugins->load_plugin($engine);
  $engine_plugin->register($mojo, $param);

  $mojo->helper(
    search => sub {
      my $c = shift;

      # If there is no callback, return the hits object!
      my $cb = pop if ref $_[-1] && ref $_[-1] eq 'CODE';

      my %param = @_;

      # Get count
      $c->stash('search.count' => (
	delete $param{count} //
	  scalar($c->param('count')) //
	    $plugin->items_per_page
	  )) unless $c->stash('search.count');

      # Get startPage
      $c->stash('search.startPage' => (
	delete $param{startPage} //
	  scalar($c->param('startPage')) //
	    1
	  )) unless $c->stash('search.startPage');

      # Set items_per_page
      my $items_per_page =
	$c->stash('search.count') > $plugin->items_per_page ?
	  $plugin->items_per_page : $c->stash('search.count');

      # Make sure the values are numerical
      foreach (map { 'search.' . $_ } qw/startPage count/) {
	if (!$c->stash($_) || $c->stash($_) !~ /^\d+$/) {
	  $c->stash($_ => undef);
	};
      };

      $c->stash('search.itemsPerPage' => $items_per_page);
      $c->stash('search.totalResults' => 0);
      $c->stash('search.hits' => []);

      # TODO: Don't do this, in case there is already search.hits set by async!

      # Here's the special suff
      $engine_plugin->search($c, %param);

      my $v = $cb->();
      foreach (qw/hits totalResults itemsPerPage/) {
	delete $c->stash->{'search.' . $_};
      };
      return $v;
    }
  );

  # Establish search_hits tag helper
  $mojo->helper(
    search_hits => sub {
      my $c = shift;
      my $cb = pop;

      if (!ref $cb || !(ref $cb eq 'CODE')) {
	$c->app->log->error('search_hits expects a code block');
	return '';
      };

      # Get hits
      my $hits = delete $c->stash->{'search.hits'} or return '';

      # Iterate over hits
      my $string;
      foreach (@$hits) {
	local $_ = $_;
	$c->stash('search.hit' => $_);
	$string .= $cb->($_);
      };

      delete $c->stash->{'search.hit'};
      return b($string // '');
    }
  );
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
    engine => 'Lucy',
    items_per_page => 25,
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
      my $mojo = shift;
      my $lucy = $mojo->lucy;
      $lucy->add(
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
    my $c = shift;
    # Set query based on parameter
    $c->stash('search.query' => scalar $c->param('q'));
    $c->render('index');
  };

  app->start;

  __DATA__

  @@ layout/default.html.ep
  <html>
    <head><title><%= title %></title></head>
    <body><% content %></body>
  </html>

  @@ index.html.ep
  % layout 'default', title => 'Search';

  %# Set search form
  %= form_for url_for, begin
  %=   search_field 'q'
  % end

  %# Show search results
  %= search begin
  <p>Found <%= stash 'search.totalResults' %> matches</p>
  <ul>
  %=   search_hits begin
  <li>
    <h3><%= link_to $_->{title}, $_->{url} %></h3>
    <p><%= $_->{content} %></p>
  </li>
  %   end
  </ul>
  % end


=head1 DESCRIPTION

L<Mojolicious::Plugin::Search> is a base plugin to add
search capabilities to Mojolicious.

B<This is early software, please use it with care.>


=head1 METHODS

L<Mojolicious::Plugin::Search> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.


=head2 register

Called when registering the plugin.
All parameters can be set either on registration or as part
of the configuration file with the key C<Search>.

Accepts the following parameters:

=over 2

=item B<items_per_page>

Set the default number of hits shown per page.

=item B<engine>

A L<Mojolicious::Plugin::Search> engine. Defaults to
L<Lucy|Mojolicious::Plugin::Search::Lucy>. See
L<Mojolicious::Plugin::Lucy> for further information.

=back

All further parameters are passed to the chosen engine.


=head1 HELPERS

=head2 search

  %= search begin
  %# ...
  % end

Starts a code block for searches. Accepts engine specific parameters.

The parameters
C<query>, C<startIndex>, and C<count> can be passed
using the stash if prefixed with C<search.>.

In C<search> the stash value C<search.totalResults> will contain
the number of total results (if available).
The stash value C<search.hits> will contain an array reference
including all matches.
The stash value C<search.itemsPerPage> will contain the number
of matches shown per page (this may differ from the requested
C<count> value).


=head2 search_hits

  %= search begin
  %=  search_hits begin
  %# ...
  %   end
  % end

Iterates over all search hits for a certain query, contains a hit object
in C<$_>. The concrete realization is engine specific.

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
