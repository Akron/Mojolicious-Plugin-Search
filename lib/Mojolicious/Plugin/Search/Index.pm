package Mojolicious::Plugin::Search::Index;
use Mojo::Base -base;
use Mojo::Collection;
use Scalar::Util 'blessed';
use POSIX 'ceil';

has [qw/controller engine query items_per_page/];
has start_page => 1;
has total_results => -1;

# Get total pages
sub total_pages {
  my $self = shift;
  return 0 if $self->total_results <= 0;
  return ceil($self->total_results / ($self->items_per_page || 1));
};


# Get or set results
sub results {
  my $self = shift;
  if (@_ > 0) {
    return $self->{results} = Mojo::Collection->new(@_);
  };
  return $self->{results} // Mojo::Collection->new;
};


# Get or set wanted start index
sub start_index {
  my $self = shift;
  if ($_[0]) {
    $self->{start_index} = $_[0];
    return;
  };

  return $self->{start_index} //
    ($self->start_page - 1) * $self->items_per_page;
};


# Get hit
sub hit {
  return $_[0]->results->[$_[1] // 0];
};


# Call autoload
sub AUTOLOAD {
  my $self = shift;

  # Get some information
  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;

  # Call method on engine
  my $engine = $self->engine;
  if ($engine->can($method)) {
    return $engine->$method($self, @_);
  };

  # Croak on problem
  Carp::croak qq{Can't locate object method "$method" via package } .
      blessed $engine;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Search::Index - Index object for Search


=head1 SYNOPSIS

  use Mojolicious::Plugin::Search::Index;

  my $index = Mojolicious::Plugin::Search::Index->new(
    controller => Mojolicious::Controller->new(...),
    engine     => $engine
  );

  $index->query("tree AND forest");
  $index->total_results(7);

=head1 DESCRIPTION

L<Mojolicious::Plugin::Search::Index> is a proxy object for search engines,
used by L<Mojolicious::Plugin::Search>.

=head1 ATTRIBUTES

=head2 controller

  $index->controller(Mojolicious::Controller->new);
  print $index->controller->stash('search.hit');

Get or set the controller object.
Normally set by L<Mojolicious::Plugin::Search>.


=head2 engine

  $index->controller(Mojolicious::Plugin::Search::Lucy->new);
  print $index->controller->stash('search.hit');

Get or set the controller object.
Normally set by L<Mojolicious::Plugin::Search>.


=head2 hit

  print $index->hit(0)->{title};

Get a hit by providing an index integer.
Only hits in the scope of search are accessible.
Normally set by a L<search|Mojolicious::Plugin::Search/search>.


=head2 items_per_page

  $index->items_per_page(20);
  print $index->items_per_page;

Get or set the number of items to show per page.
Defaults to the value of the calling
L<Mojolicious::Plugin::Search/items_per_page|plugin>.


=head2 query

  $index->query("tree OR forest);
  print $index->query;

Get or set the query term of the search.

=head2 results

  $index->results({
    title => 'Foo'
  },{
    title => 'Bar'
  });

  say $index->results->map(sub { $_->{title} })->join(', ');

Set search results as an array or return search results as
a L<Mojo::Collection>.


=head2 start_index

  $index->start_index(3);
  print $index->start_index;

Get or set the start index for offsets of search results.
Defaults to the calculated value based on L<start_page|/start_page>
and L<items_per_page|/items_per_page>.


=head2 start_page

  $index->start_page(2);
  print $index->start_page;

Get or set the start page for offsets of search results.
Defaults to C<1>.


=head2 total_pages

  print $index->total_pages;

Get the number of pages of results based on the values of
L<total_results|/total_results> and L<items_per_page|/items_per_page>.


=head2 total_results

  $index->total_results(3);
  print $index->total_results;

Get or set the number of total_results of a search.
Normally set by a L<search|Mojolicious::Plugin::Search/search>.


=head1 AUTOLOAD

In addition to the L<ATTRIBUTES|/ATTRIBUTES> above, the object autoloads
further methods provided by the associated engine. Methods called on the
object but provided by the engine will get the C<index> object passed as
the second argument after the invocant and followed by further parameters.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Search


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut

