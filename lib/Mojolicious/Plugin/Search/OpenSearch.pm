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

  # Add templates
  push @{$mojo->renderer->paths}, catdir(dirname(__FILE__), 'OpenSearch','templates');

  my $helpers = $mojo->renderer->helpers;

  # Get callback plugin
#  unless (exists $helpers->{callback}) {
#    $mojo->plugin('Util::Callback');
#  };

  # Check for 'search' callback
#  $mojo->callback([qw/search/] => $param, -once);

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

  # # Per Hook nachschauen, ob per shortcut der Pfad besetzt ist.

  # # Establish 'render_opensearch' helper
  # $mojo->helper(
  #   render_opensearch => sub {
  #    my $c = shift;
  #    my $query = shift;
  #    my $result = shift;
  #  }
  #);

  # Establish 'opensearch' shortcut
  $mojo->routes->add_shortcut(
    opensearch => sub {
      my $r = shift;
      my %osparam = @_;

      my $item = delete $osparam{item};

      if (!$item || ref $item ne 'CODE') {
	$mojo->log->error('No item callback established');
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
      foreach (@osattr, qw/inputEncoding outputEncoding/) {
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
	    item => $item
	  );

	  # my $result = $c->callback( opensearch => \%query );

	  # Todo: Transform outputEncoding
	  # $c->render(text => $result);

	  # Await:
	  # totalResults
	  # itemsPerPage
	  # updated

#   <opensearch:totalResults>4230000</opensearch:totalResults>
#   <opensearch:startIndex>21</opensearch:startIndex>
#   <opensearch:itemsPerPage>10</opensearch:itemsPerPage>
#   <opensearch:Query role="request" searchTerms="New York History" startPage="1" />

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


plugin 'Search::OpenSearch' => {
  short_name => '',
  description => '',
  language => 'en-us',
  long_name => '',
  developer => '',
  contact => '',
  adult_content => '',
  attribution => '',
  syndication_right => ''
};


$r->get('/search/open')->opensearch(
  searchTerms => 'q',
  startPage => 'page',
  item => sub {
    my ($c, $hit) = @_;
    return {
      title => $hit->{title},
      link => $hit->{url},
      snippet => $hit->{highlight}
    }
  }
);


optional

'file' => 'path of opensearch.xml' (defaults to C<./well-known/opensearch.xml>)

count =>
startPage
startIndex
startPage
language
format
searchTerms
inputEncoding
outputEncoding

endpoint 'opensearch-description'
defaults to C<./well-known/opensearch.xml>
