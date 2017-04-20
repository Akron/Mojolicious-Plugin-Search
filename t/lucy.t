#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use Mojo::ByteStream 'b';
use Mojo::File;
use lib '../lib', 'lib', 't';
use File::Temp 'tempdir';

my $tempdir = tempdir();

# - Test with boost

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
    # Set directly
    url => {
      type => 'string',
      indexed => 0
    }
  },
  highlighter => {
    pre_tag => '<span class="match">',
    post_tag => '</span>',
    excerpt_length => 120
  },
  on_init => sub {
    my $engine = shift;
    my $app = $engine->controller->app;
    $app->log->info('Initial indexing');
    my $path = $app->home . '/sample';

    unless (opendir(SAMPLE, $path)) {
      fail("Unable to open $path");
      return;
    };

    my @docs;
    foreach my $filename (readdir(SAMPLE)) {
      if ($filename =~ /\.txt$/) {
        my $text = Mojo::File->new($path . '/' . $filename)->slurp;
        $text =~ /\A(.+?)^\s+(.*)/ms
	  or die 'Can\'t extract title/bodytext';

	my ($title, $bodytext) = ($1, $2);
	$title =~ s/\s+$//;
	$bodytext =~ s/\s+//;
	push(@docs, {
	  title   => $title,
	  content => $bodytext,
	  url     => "/text/$filename",
	  # -boost  => 4
	});
      };
    };
    closedir(SAMPLE);

    $engine->add( @docs );
  }
};

# search with stash
get '/' => sub {
  my $c = shift;
  my $query = $c->param('q');
  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
%= search highlight => 'content', begin
  <head><title><%= search->query %></title></head>
  <body>
<p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%=   search_results begin
<div>
  <h1><a href="<%= $_->{url} %>"><%= $_->{title} %></a></h1>
  <p class="excerpt"><%= search->snippet %></p>
  <p class="score"><%= $_->get_score %></p>
</div>
%   end
  </body>
% end
</html>
TEMPLATE

  return $c->render(
    inline => $template,
    'search.query'      => scalar $c->param('q'),
    'search.start_page' => scalar $c->param('page'),
    'search.count'      => scalar $c->param('count')
  );
};

get '/search' => sub {
  my $c = shift;
  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
%= search query => param('q'), start_page => param('page'), count => param('count'), highlight => 'content', begin
  <head><title><%= search->query %></title></head>
  <body>
<p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%=   search_results begin
<div>
  <h1><a href="<%= $_->{url} %>"><%= $_->{title} %></a></h1>
  <p class="excerpt"><%= search->snippet %></p>
  <p class="score"><%= $_->get_score %></p>
</div>
%   end
  </body>
% end
</html>
TEMPLATE
  return $c->render(inline => $template);
};


my $t = Test::Mojo->new;

# Search with stash
$t->get_ok('/?q=test')
  ->text_is('head title', 'test')
  ->text_is('#totalResults', 1)
  ->text_is('h1 a', 'Article VI')
  ->element_exists('h1 a[href=/text/art6.txt]')
  ->text_like('p.excerpt', qr/Office/);

$t->get_ok('/?q=the')
  ->text_is('head title', 'the')
  ->text_is('#totalResults', 51)
  ->element_exists('h1 a[href=/text/amend10.txt]')
  ->text_like('p.excerpt span.match', qr/^the$/i);

# Search with params
$t->get_ok('/search?q=test')
  ->text_is('head title', 'test')
  ->text_is('#totalResults', 1)
  ->text_is('h1 a', 'Article VI')
  ->element_exists('h1 a[href=/text/art6.txt]')
  ->text_like('p.excerpt', qr/Office/);

$t->get_ok('/search?q=the')
  ->text_is('head title', 'the')
  ->text_is('#totalResults', 51)
  ->element_exists('h1 a[href=/text/amend10.txt]')
  ->text_like('p.excerpt span.match', qr/^the$/i);

# Search directly - access results
my $c = $t->app->build_controller;
my $e = $c->search(query => 'test');
is($e->total_results, 1, 'Total Results');
is($e->query, 'test', 'Query');
is($e->hit(0)->{title}, 'Article VI', 'Title');
is($e->hit(0)->{url}, '/text/art6.txt' , 'URL');
like($e->hit(0)->{content}, qr/^All\s*Debts contracted/ , 'Content');
is($e->results->[0]->{title}, 'Article VI', 'Title');
is($e->results->[0]->{url}, '/text/art6.txt' , 'URL');
like($e->results->[0]->{content}, qr/Office/ , 'Content');
ok(!defined $e->hit(1), 'No more hits');

$e = $c->search(query => 'the');
is($e->total_results, 51, 'Total Results');
is($e->query, 'the', 'Query');

is($e->start_page,    1, 'Current page');
is($e->items_per_page, 25, 'Items per page');
is($e->total_pages,     3, 'Total pages');
is($e->start_index,     0, 'start index');

is($e->hit(0)->{title}, 'Amendment X', 'Title');
is($e->hit(0)->{url}, '/text/amend10.txt' , 'URL');
like($e->hit(0)->{content}, qr/^The\s*powers not delegated/, 'Content');

is($e->results->[1]->{title}, 'Amendment XVIII', 'Title');
is($e->results->[1]->{url}, '/text/amend18.txt' , 'URL');
like($e->results->[1]->{content}, qr/^1\.\s*After one year/, 'Content');


# Search non-blocking
get '/search-nb' => sub {
  my $c = shift;
  $c->search(
    query => $c->param('q'),
    count => $c->param('count'),
    start_page => $c->param('page'),
    highlight => 'content',
    cb => sub {
      return $c->render(template => 'search');
    }
  );
};

# Check non-blocking
$t->get_ok('/search-nb?q=the')
  ->text_is('head title', 'the')
  ->text_is('#totalResults', 51)
  ->element_exists('h1 a[href=/text/amend10.txt]')
  ->text_like('p.excerpt span.match', qr/^the$/i);

$t->get_ok('/search-nb?q=test')
  ->text_is('head title', 'test')
  ->text_is('#totalResults', 1)
  ->text_is('h1 a', 'Article VI')
  ->element_exists('h1 a[href=/text/art6.txt]')
  ->text_like('p.excerpt', qr/Office/);


done_testing;

__DATA__

@@ search.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= search->query %></title></head>
  <body>
    <p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%= search_results begin
    <div>
      <h1><a href="<%= $_->{url} %>"><%= $_->{title} %></a></h1>
      <p class="excerpt"><%= search->snippet %></p>
      <p class="score"><%= $_->get_score %></p>
    </div>
% end
  </body>
</html>

__END__
