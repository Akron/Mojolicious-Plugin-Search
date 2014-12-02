package Mojolicious::Plugin::Search::Lucy;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

use Scalar::Util qw/blessed weaken/;
use File::Temp 'tempdir';

use Lucy::Plan::Schema;
use Lucy::Index::Indexer;
use Lucy::Search::QueryParser;

# FieldTypes
use Lucy::Plan::FullTextType;
use Lucy::Plan::StringType;
use Lucy::Plan::BlobType;

# Default Analyzer
use Lucy::Analysis::PolyAnalyzer;

# Highlighter
use Lucy::Highlight::Highlighter;

our $UNKNOWN = ' has an unknown field type';

# Establish engine
sub register {
  my ($plugin, $app, $index_class, $param) = @_;
  $param ||= {};

  # Create a schema
  my $schema = $param->{schema};
  unless ($schema) {
    $app->log->warn('No schema given for ' . __PACKAGE__);
    return;
  };

  $plugin->{truncate} = delete $param->{truncate};

  # Get language information
  my $language = $param->{language} // 'en';

  # Set highlighter parameters
  $plugin->_highlighter($param->{highlighter} // {});

  # Possibly an analyzer is given
  my $analyzer = $param->{analyzer};

  # Get fields
  my $fields = $param->{fields} // {};

  # Iterate through all schema keys
  foreach my $name (keys %$fields) {
    my $field = $fields->{$name};

    unless ($fields->{$name} = _get_type($fields->{$name}, $analyzer, $language)) {
      $app->log->warn($name . $UNKNOWN);
    };
  };

  # Create new schema
  my $real_schema = Lucy::Plan::Schema->new;

  # Iterate through all schema keys
  foreach my $name (keys %$schema) {

    my $ft;

    # Get by field type name
    unless (ref $schema->{$name}) {
      $ft = $fields->{$schema->{$name}};
    }

    # Get by data structure
    else {
      $ft = _get_type($schema->{$name}, $analyzer, $language);
    };

    # Get type
    unless ($ft) {
      $app->log->warn($name . $UNKNOWN);
      next;
    };

    # Specify fields
    $real_schema->spec_field(
      name => $name,
      type => $ft
    );
  };

  # Set schema
  $plugin->{schema} = $real_schema;

  # No path is given - use temporary path
  my $tempdir;
  unless ($param->{path}) {
    $tempdir = tempdir();
    for ($app->log) {
      $_->warn('There is no index path given for ' . __PACKAGE__);
      $_->warn(__PACKAGE__ . ' is now using temporary path ' . $tempdir);
    };
    $plugin->path(undef, $tempdir);
  }

  # Path is given
  else {
    $plugin->path(undef, $param->{path});
  };

  # Modify later, just in case
  $plugin->{query} = Lucy::Search::QueryParser->new(
    schema => $plugin->{schema}
  );

  # on init:
  # delete $plugin->{searcher};

  # Cleanup later
  # lucy.highlight
};


# Search method
sub search {
  my $self = shift;
  my $index = shift;

  # Get callback
  my $cb = pop
    if $_[-1] && ref $_[-1] && ref $_[-1] eq 'CODE';

  my %param = @_;

  # Get query
  my $query = $index->query or return '';

  # Query may be a string
  $query = $self->query_obj($query) unless blessed $query;

  # Query may be a stringifiable object
  unless ($query->isa('Lucy::Search::Query')) {
    $query = $self->query_obj("$query");
  };

  # Create highlighters
  if ($param{highlight}) {

    # Multiple highlights have to be objects
    my $hls = ref $param{highlight} ?
      $param{highlight} : { $param{highlight} => {} };

    my %highlight;

    # Create highlighter for each field
    foreach my $hl (keys %$hls) {
      my $obj = $hls->{$hl};

      # Create a lucy highlight object
      my $highlight = Lucy::Highlight::Highlighter->new(
	field    => $hl,
	searcher => $self->searcher,
	query    => $query,
	excerpt_length => $obj->{excerpt_length}
	  // $self->_highlighter('excerpt_length') // 200
	);

      my $pre_tag  = $obj->{pre_tag}  // $self->_highlighter('pre_tag');
      my $post_tag = $obj->{post_tag} // $self->_highlighter('post_tag');

      # Maybe set per highlighter
      $highlight->set_pre_tag($pre_tag)   if $pre_tag;
      $highlight->set_post_tag($post_tag) if $post_tag;

      $highlight{$hl} = $highlight;
    };

    # Set highlight stash
    $index->controller->stash('lucy.highlight' => \%highlight);
  };

  # Find the hits
  my $hits = $self->searcher->hits(
    query      => $query,
    offset     => $param{start_index} // $index->start_index,
    num_wanted => $index->items_per_page
  );

  $index->total_results($hits->total_hits);

  my (@hits, $hit);
  push(@hits, $hit) while $hit = $hits->next;

  # Set hits
  $index->results(@hits);

  return $cb->($index) if $cb;
  return 1;
};


# Add new documents to the index
sub add {
  my $self = shift;
  my $index = shift;

  my $commit = 1;
  if ($_[-1] eq '-no_commit') {
    $commit = 0;
    pop;
  };

  my $i = $self->_new_indexer(create => 1)
    or return;

  foreach my $doc (@_) {
    if (exists $doc->{-boost}) {
      my $boost = delete $doc->{-boost};
      $i->add_doc(doc => $doc, boost => $boost);
    }
    else {
      $i->add_doc($doc);
    }
  };

  if ($commit) {
    delete $self->{searcher};
    return $i->commit;
  };

  return 1;
};


# Remove documents from the index
sub delete {
  my $self = shift;
  my $index = shift;

  my $commit = 1;
  if ($_[-1] eq '-no_commit') {
    $commit = 0;
    pop;
  };

  my $i = $self->_new_indexer or return;

  # delete by query
  if (@_ == 1) {
    $i->delete_by_query($self->query_obj($_[0]));
  }
  # delete by term
  else {
    my $field = shift;
    if (ref $_[0]) {
      foreach (@{$_[0]}) {
	$i->delete_by_term(field => $field, term => $_);
      };
    }
    else {
	$i->delete_by_term(field => $field, term => shift);
    }
  };

  if ($commit) {
    delete $self->{searcher};
    return $i->commit;
  };
  return 1;
};


# Commit changes to the index
sub commit {
  my $self = shift;
  my $i = $self->_new_indexer or return;
  delete $self->{searcher};
  return $i->commit;
};


# Extract snippet
sub snippet {
  my ($self, $index, $field) = @_;
  my $c = $index->controller;

  state $msg = 'You need to define this highlighter';

  my $hl = $c->stash('lucy.highlight');

  # No highlighter object was defined
  unless ($hl) {
    $c->app->log->warn($msg);
    return '';
  };

  return '' unless $c->stash('search.hit');

  # Get highlighter (the first if nothing is defined)
  my ($highlight) = $field ? $hl->{$field} : values %$hl;

  # No highlighter defined
  unless ($highlight) {
    $c->app->log->warn($msg);
    return '';
  };

  return b($highlight->create_excerpt($c->stash('search.hit')) || '');
};



# The searcher object
sub searcher {
  my $plugin = shift;

  # Has only to be rebuild if something changed
  return ($plugin->{searcher} //= Lucy::Search::IndexSearcher->new(
    index => $plugin->path
  ));
};


# The index path
sub path {
  my $plugin = shift;
  if (@_ == 2) {
    return $plugin->{path} = pop;
  };
  return $plugin->{path}
};


# Create query object
sub query_obj {
  my $plugin = shift;
  my $q = pop;
  $plugin->{query}->parse( "$q" );
};


# Get new indexer
sub _new_indexer {
  my $self = shift;

  return Lucy::Index::Indexer->new(
    index    => $self->path,
    schema   => $self->{schema},
    truncate => $self->{truncate},
    @_
  );
};

sub _highlighter {
  my $self = shift;
  if (ref $_[0]) {
    $self->{_highlighter} = shift;
    return;
  };
  $self->{_highlighter}->{$_[0]};
};

sub _get_type {
  my $field = shift;
  my $type = lc($field->{type}) // 'fulltext';

  my %type;
  $type{stored} = $field->{stored} if exists $field->{stored};

  # fields for indexable field types
  if ($type ne 'blob') {
    for (qw/boost indexed sortable/) {
      $type{$_} = $field->{$_} if exists $field->{$_};
    };
  };

  # FullTextType
  if ($type eq 'fulltext') {
    my ($analyzer, $language) = @_;
    my $tanalyzer = $field->{analyzer} // $analyzer;

    unless ($tanalyzer) {
      $tanalyzer = Lucy::Analysis::PolyAnalyzer->new(
	language => $language
      );
    }
    elsif (!blessed $analyzer) {
      warn 'No valid analyzer defined for fulltext';
    };

    # Set analyzer
    $type{analyzer} = $tanalyzer;

    # Set highlightable
    if (exists $field->{highlightable}) {
      $type{highlightable} = $field->{highlightable}
    };

    # Create fulltext type fields
    return Lucy::Plan::FullTextType->new( %type );
  }

  # StringType
  elsif ($type eq 'string') {
    return Lucy::Plan::StringType->new( %type );
  }

  # BlobType
  elsif ($type eq 'blob') {
    return Lucy::Plan::BlobType->new( %type );
  };

  # Fail to recognize field type
  return;
};


1;


__END__


=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Search::Lucy - Lucy Engine for Mojolicious::Plugin::Search


=head1 SYNOPSIS

  # Load plugin in Mojolicious
  plugin Search => {
    engine => 'Lucy',
    path => app->home .'/index',
    schema => {
      title => 'fulltext',
      content => {
        type => 'fulltext',
        highlightable => 1
        stored => 1
      },
      url => 'string'
    }
  };

  # Add document to the index
  $c->search->add({
    title => 'My first Article',
    content => 'This is my first blog post'
  });

  # Show search results in a template
  %= search highlight => 'content', begin
  <p>Matches: <%= search->total_results %></p>
  %=   search_results begin
  <div>
    <h1><%= link_to $_->{title} => $_->{url} %></h1>
    <p><%= search->snippet %></p>
    <p class="score"><%= $_->get_score %></p>
  </div>
  %   end
  % end


=head1 DESCRIPTION

L<Mojolicious::Plugin::Search::Lucy> is a search engine for
L<Mojolicious::Plugin::Search>, that is based on L<Apache Lucy|Lucy>.

For further information on L<Lucy>, please refer to the documentation,
the L<tutorial|Lucy::Docs::Tutorial>, and the L<cookbook|Lucy::Docs::Cookbook>.

B<This is early software, please use it with care.>


=head1 METHODS

L<Mojolicious::Plugin::Search::Lucy> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.


=head2 register

plugin Search => {
  engine => 'Lucy',
  path => $tempdir . '/index',
  fields => {
    ftt => {
      type => 'fulltext',
      highlightable => 1,
      stored => 1
    }
  },
  schema => {
    content => 'ftt',
    title => 'ftt',
    url => {
      type => 'string',
      indexed => 0
    }
  };


Called when the plugin is registered by L<Mojolicious::Plugin::Search>,
using the keyword C<engine> with the value C<Lucy>.
Accepts the following additional parameters
(which are passed by L<Mojolicious::Plugin::Search>):

=over 2

=item B<analyzer>

This is expected to be a L<Lucy::Analysis::Analyzer> object.
Defaults to L<Lucy::Analysis::PolyAnalyzer> for the language
given by C<language>.


=item B<language>

Defines the language of the Index, probably used by the
fulltext analyzers. Defaults to C<en>.


=item B<truncate>

A boolean value indicating that the previous index data
may be discarded after a successfull index commit.


=item B<create>

A boolean value indicating that a new index should be
created unless it already exists.


=item B<fields>

L<Mojolicious::Plugin::Search::Lucy> expects a defined index schema
(other than L<Lucy::Lite>), which gives the
user the full power of L<Lucy>. Fields can be either defined
using the C<fields> keyword or per field in the C<schema>.

C<fields> is a hash reference, with the name of the field type as a string
and the object values as hash references. The object values can define
the following parameters:

=over 4

=item B<type>

Expects one of the following strings: C<FullText>,
C<String>, or C<Blob>. It defaults to C<FullText>.

Depending on the C<type>, the following additional
parameters are allowed:

=item B<stored>

A boolean value indicating whether the field should be stored.
Defaults to C<true>.


=item B<boost>

A floating point number to boost per-field.
Defaults to C<1.0>. Not available in C<Blob>.


=item B<indexed>

boolean value indicating whether the field should be indexed.
Defaults to C<true>. Not available in C<Blob>.


=item B<sortable>

A boolean value indicating whether the field should be sortable.
Not available in C<Blob>.


=item B<highlightable>

A boolean value indicating whether the field should be
highlightable. Only available in C<FullText>.

=back


=item B<schema>

Defines the schema as a hash reference. The reference has the name of the
field associated to either a string defining the field type or a
hash reference defining the field type as in C<fields>.


=item B<analyzer>

Set an analyzer object.
Defaults to L<Lucy::Analysis::PolyAnalyzer> with the given C<language>.
The analyzer only applies to C<FullText> fields.


=item B<highlighter>

Set the default values for highlighting as a hash reference.
Accepts the following keys:

=over 4

=item B<pre_tag>

The start tag of the highlighted term in the excerpt as a string.

=item B<post_tag>

The end tag of the highlighted term in the excerpt as a string.

=item B<excerpt_length>

The length of the excerpt as an integer.
Defaults to C<200> characters.

=back

=back


=head2 search

  %= search highlight => 'content', begin
  <p><%= search->total_results %> matches found</p>
  %=   search_results begin
  <div>
    <h1><%= link_to $_->{title} => $_->{url} %></h1>
    <p><%= search->snippet %></p>
    <p class="score"><%= $_->get_score %></p>
  </div>
  %   end
  % end

The L<search> helper is established by L<Mojolicious::Plugin::Search>.
When used in conjunction with the L<Lucy> engine, the following additional
parameters are accepted:

=over 4

=item B<highlight>

  highlight => {
    content => {},
    title => {
      pre_tag => '[',
      post_tag => ']'
    }
  }

Expects all fields to be prepared for highlighted
snippets in L<search_results>. A single field can be given as a string.
In case of multiple fields, they have to be keys in a hash reference.
The values of the hash reference are hash references accepting the same
parameters as the C<highlight> parameter in the configuration.

=back

L<Mojolicious::Plugin::Search::Lucy> accepts the query to be a
string or a L<Lucy::Search::Query> object.


=head2 search_results

The L<search_results> helper is established by L<Mojolicious::Plugin::Search>.
When used in conjunction with the L<Lucy> engine,
The current L<Lucy::Document::HitDoc> is stored in C<$_> and in
the stash value C<search.hit>.


=head1 OBJECT ATTRIBUTES

These attributes can be accessed using the object helper
L<Mojolicious::Plugin::Search/search|search>.


=head2 path

  print $c->search->path;

The path to the index. Has to be set on registration,
otherwise a temporary directory is used.


=head2 searcher

  $c->search->searcher;

The associated L<Lucy::Search::IndexSearcher> object.


=head2 query_obj

  $c->search->query_obj("tree OR cat");

Create a L<Lucy::Search::Query> object based on a query string and
the associated query parser.


=head1 OBJECT METHODS

These methods can be accessed using the object helper
L<Mojolicious::Plugin::Search/search|search>.

=head2 add

  $c->search->add({
    title => 'My first Article',
    content => 'This is my first blog post'
  },
  {
    title => 'The Comment system',
    content => 'The comment system is now disabled',
    -boost => 2.3
  });

  $c->search->add({ title => 'yeah' }, -no_commit)

Add new documents to the index. Accepts an array of hash references
containing field and value pairs. The special parameter C<-boost>
can be used to lift or lower the ranking of the document in search
results. After all articles in the array are added an automated
commit is released.
If this is not wanted, a final C<-no_commit> will prevent this behaviour.


=head2 commit

  $c->search->commit;

Commit changes to the index. This is only necessary if automated commits after
L</add> and L</delete> were deactivated.


=head2 delete

  $c->search->delete("tree");
  $c->search->delete(title => "tree");
  $c->search->delete(id => [6,7,8]);
  $c->search->delete(id => [6,7,8], -no_commit);

Delete documents from the index by search terms,
by search terms restricted to a certain field, or by document identifier.

After all deletes are performed an automated commit is released.
If this is not wanted, a final C<-no_commit> will prevent this behaviour


=head2 snippet

  %# In templates:
  %= search highlight => 'content', begin
  %=  search_results begin
    <p><%= search->snippet 'content' %></p>
  %   end
  % end

Returns the highlighted snippet of the current match
inside a L</search_results> block.
Takes an optional field parameter or takes the
alphabetically first field defined in the C<highlight>
parameter of L</search>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Search


=head1 COPYRIGHT AND LICENSE

Parts of this documentation is based on the documentation
of L<Lucy>.

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
