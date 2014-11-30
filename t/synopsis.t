#!/usr/bin/perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use lib '../lib', 'lib', 't';



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

my $t = Test::Mojo->new;
$t->get_ok('/')
  ->text_is('title', 'Search');

$t->get_ok('/?q=ballon')
  ->text_is('title', 'Search for ballon')
  ->text_is('body > p', 'Found 2 matches')
  ->text_is('ul > li > h2 > a', 'My first Ballon')
  ->text_is('ul > li > p', 'Please find me!')
  ->text_is('ul > li:nth-child-of-type(2) > h2 > a', 'My second Ballon')
  ->text_is('ul > li:nth-child-of-type(2) > p', 'Thanks for searching');

$t->get_ok('/?q=find')
  ->text_is('title', 'Search for find')
  ->text_is('body > p', 'Found 1 matches')
  ->text_is('ul > li > h2 > a', 'My first Ballon')
  ->text_is('ul > li > p', 'Please find me!');

done_testing;

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
