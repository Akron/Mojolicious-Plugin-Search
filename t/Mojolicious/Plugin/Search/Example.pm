package Mojolicious::Plugin::Search::Example;
use Mojo::Base 'Mojolicious::Plugin';

# Contain documents
our @DOCS = ();

# Register plugin
sub register {
  my ($self, $mojo, $param) = @_;

  # Initialize some documents
  @DOCS = (
    {
      title => 'Test',
      content => 'My first example'
    },
    {
      title => 'Example!',
      content => 'My second example'
    }
  );
};

# Search method for documents
sub search {
  my ($self, $index) = @_;
  my $cb = pop
    if $_[-1] && ref $_[-1] && ref $_[-1] eq 'CODE';

  # Get parameters from index object
  my $query = $index->query;
  my $count = $index->items_per_page;
  my $start_index = $index->start_index;

  # Collect hits
  my @matches = ();
  my $total_results = 0;

  # Iterate sequentially through all docs
  foreach (grep { $_ } @DOCS) {

    # Check if the doc is a match
    if (index($_->{title}.' '.$_->{content}, $query) >= 0) {

      # Check if match is in scope
      if ($total_results >= $start_index &&
	    $total_results < ($start_index + $count)) {
	push(@matches, $_);
      };

      # Match!
      $total_results++;
    };
  };

  # Set overall matches
  $index->total_results($total_results);

  # Set result array
  $index->results(@matches);

  # Execute callback in case of non-blocking like request
  return $cb->($index) if $cb;
  return 1;
};


# Add new document
sub add {
  my ($self, $index, $obj) = @_;
  push(@DOCS, $obj);
  return 1;
};


# Delete document from index
sub delete {
  my ($self, $index, $i) = @_;
  $DOCS[$i] = undef;
  return 1;
};


1;
