#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use Mojo::ByteStream 'b';
use lib '../lib', 'lib', 't';

plugin Search => {
  engine => 'Example'
};

get '/' => sub {
  my $c = shift;
  return $c->render(text => 'fine');
};

put '/' => sub {
  my $c = shift;
  if ($c->search->add($c->req->json)) {
    return $c->render(text => 'fine');
  };
  return $c->render(text => 'fail');
};

del '/:count' => sub {
  my $c = shift;
  if ($c->search->delete($c->stash('count'))) {
    return $c->render(text => 'fine');
  };
  return $c->render(text => 'fail');
};


# search in template
get '/search-template' => sub {
  my $c = shift;
  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
%= search query => param('q'), count => param('count'), start_page => param('page'), begin
   <head><title><%= search->query %></title></head>
  <body>
<p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%=  search_results begin
  <div>
    <h1><%= $_->{title} %></h1>
    <p><%= $_->{content} %></p>
  </div>
%   end
  </body>
% end
</html>
TEMPLATE
  return $c->render(inline => $template);
};

# search in template
get '/search-pre' => sub {
  my $c = shift;

  my $e = $c->search(
    query => $c->param('q'),
    count => $c->param('count'),
    start_page => $c->param('page')
  );

  ok($e->total_results,  'Total results are fine');
  ok($e->start_page,     'Current page is fine');
  ok($e->items_per_page, 'Items per page is fine');
  ok($e->total_pages,    'Total pages is fine');

  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
  <head><title><%= search->query %></title></head>
  <body>
  <p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%= search_results begin
  <div>
    <h1><%= $_->{title} %></h1>
    <p><%= $_->{content} %></p>
  </div>
% end
  </body>
</html>
TEMPLATE
  return $c->render(inline => $template);
};

# search in template
get '/search-nb' => sub {
  my $c = shift;
  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
  <head><title><%= search->query %></title></head>
  <body>
    <p>Hits: <span id="totalResults"><%= search->total_results %></span></p>
%= search_results begin
    <div>
      <h1><%= $_->{title} %></h1>
      <p><%= $_->{content} %></p>
    </div>
% end
  </body>
</html>
TEMPLATE
  $c->search(
    query => $c->param('q'),
    count => $c->param('count'),
    start_page => $c->param('page'),
    cb => sub {
      return $c->render(inline => $template);
    }
  );
};


# search in template
get '/search-nb-template' => sub {
  my $c = shift;
  $c->search(
    query => $c->param('q'),
    count => $c->param('count'),
    start_page => $c->param('page'),
    template => 'search'
  );
};


my $t = Test::Mojo->new;

# Ping
$t->get_ok('/')
  ->content_is('fine');

# First added
$t->put_ok('/' => json => {
  title => 'New example Title 1',
  content => 'This is a new example'
})->content_is('fine');

# Second added
$t->put_ok('/' => json => {
  title => 'New example Title 2',
  content => 'And another test'
})->content_is('fine');

$t->get_ok('/search-template?q=example')
  ->text_is('#totalResults', 4)
  ->text_is('title', 'example')
  ->text_is('div:nth-child-of-type(1) > h1', 'Test')
  ->text_is('div:nth-child-of-type(1) > p',  'My first example')
  ->text_is('div:nth-child-of-type(2) > h1', 'Example!')
  ->text_is('div:nth-child-of-type(2) > p',  'My second example')
  ->text_is('div:nth-child-of-type(3) > h1', 'New example Title 1')
  ->text_is('div:nth-child-of-type(3) > p',  'This is a new example')
  ->text_is('div:nth-child-of-type(4) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(4) > p',  'And another test');

$t->get_ok('/search-template?q=second')
  ->text_is('#totalResults', 1)
  ->text_is('div:nth-child-of-type(1) > h1', 'Example!')
  ->text_is('div:nth-child-of-type(1) > p',  'My second example');

$t->get_ok('/search-template?q=example&count=2&page=2')
  ->text_is('#totalResults', 4)
  ->text_is('div:nth-child-of-type(1) > h1', 'New example Title 1')
  ->text_is('div:nth-child-of-type(1) > p',  'This is a new example')
  ->text_is('div:nth-child-of-type(2) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(2) > p',  'And another test');

# Third deleted
$t->delete_ok('/2')->content_is('fine');

$t->get_ok('/search-template?q=example&count=2&page=2')
  ->text_is('#totalResults', 3)
  ->text_is('div:nth-child-of-type(1) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(1) > p',  'And another test');

# Search pre
$t->get_ok('/search-pre?q=example')
  ->text_is('#totalResults', 3)
  ->text_is('div:nth-child-of-type(1) > h1', 'Test')
  ->text_is('div:nth-child-of-type(1) > p',  'My first example')
  ->text_is('div:nth-child-of-type(2) > h1', 'Example!')
  ->text_is('div:nth-child-of-type(2) > p',  'My second example')
  ->text_is('div:nth-child-of-type(3) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(3) > p',  'And another test');

# Search non-blocking with callback
$t->get_ok('/search-nb?q=example')
  ->text_is('#totalResults', 3)
  ->text_is('div:nth-child-of-type(1) > h1', 'Test')
  ->text_is('div:nth-child-of-type(1) > p',  'My first example')
  ->text_is('div:nth-child-of-type(2) > h1', 'Example!')
  ->text_is('div:nth-child-of-type(2) > p',  'My second example')
  ->text_is('div:nth-child-of-type(3) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(3) > p',  'And another test');

# Search non-blocking with template
$t->get_ok('/search-nb-template?q=example')
  ->text_is('#totalResults', 3)
  ->text_is('div:nth-child-of-type(1) > h1', 'Test')
  ->text_is('div:nth-child-of-type(1) > p',  'My first example')
  ->text_is('div:nth-child-of-type(2) > h1', 'Example!')
  ->text_is('div:nth-child-of-type(2) > p',  'My second example')
  ->text_is('div:nth-child-of-type(3) > h1', 'New example Title 2')
  ->text_is('div:nth-child-of-type(3) > p',  'And another test');

# Search directly - access results
my $c = $t->app->build_controller;
my $e = $c->search(
  query => 'My',
  count => 2,
  start_page => 1
);

is($e->total_results,  2, 'Total results are fine');
is($e->start_page,     1, 'Current page is fine');
is($e->items_per_page, 2, 'Items per page is fine');
is($e->total_pages,    1, 'Total pages is fine');

$e = $c->search(
  query => 'example',
  count => 1,
  start_page => 2
);

is($e->total_results,  3, 'Total results are fine');
is($e->start_page,     2, 'Current page is fine');
is($e->items_per_page, 1, 'Items per page is fine');
is($e->total_pages,    3, 'Total pages is fine');

$e = $c->search(
  query => 'example',
  count => 2,
  start_page => 2
);

is($e->total_results, 3,  'Total results are fine');
is($e->start_page, 2,   'Current page is fine');
is($e->items_per_page, 2, 'Items per page is fine');
is($e->total_pages, 2, 'Total pages is fine');

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
      <h1><%= $_->{title} %></h1>
      <p><%= $_->{content} %></p>
    </div>
% end
  </body>
</html>

__END__
