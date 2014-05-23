#!/usr/bin/env perl
use Test::More;
use Test::Mojo;
use Mojolicious::Lite;
use lib '../lib';

# Load plugin in Mojolicious
plugin Search => {
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
  itemsPerPage => 20,
  # Initialize index with some documents
  on_init => sub {
    my $mojo = shift;
    my $lucy = $mojo->lucy;
    $lucy->add(
      {
	title => 'My first Article',
	content => 'Please find me!',
	url => '/page1'
      },
      {
	title => 'My second Balloon',
	content => 'Thanks for searching my balloon',
	url => '/page2'
      }
    );
  }
};

plugin 'Search::OpenSearch' => {
  short_name => 'My Search',
  description => 'Search my site',
};

get('/opensearch')->opensearch(
  searchTerms => 'q',
  count => 'show',
  language => 'lang',
  startPage => 'p',
  hit => sub {
    my ($c, $i) = @_;
    return {
      title   => $i->{title},
      link    => $c->url_for($i->{url})->to_abs,
      snippet => $i->{content}
    }
  }
);

my $t = Test::Mojo->new;

my $path = '/.well-known/opensearch.xml';

$t->get_ok($path)
  ->text_is('ShortName', 'My Search')
  ->text_is('Description', 'Search my site')
  ->element_exists('Url[type=application/opensearchdescription+xml][template=/.well-known/opensearch.xml]');

my $url = $t->ua->get($path)->res->dom('Url[type=application/atom+xml]')->attr('template');
like($url, qr/format=atom/, 'Contains atom');
like($url, qr/\/opensearch\?/, 'correct path');
like($url, qr/show=\{count\?\}/, 'correct path');
like($url, qr/lang=\{language\?\}/, 'correct path');
like($url, qr/p=\{startPage\?\}/, 'correct path');
like($url, qr/q=\{searchTerms\}/, 'correct path');

my $result_atom = app->endpoint($url => { searchTerms => 'balloon', '?' => undef });
like($result_atom, qr/q=balloon/, 'Correct searchTerms');
like($result_atom, qr/format=atom/, 'Correct searchTerms');

$url = $t->ua->get($path)->res->dom('Url[type=application/rss+xml]')->attr('template');
like($url, qr/format=rss/, 'Contains atom');
like($url, qr/\/opensearch\?/, 'correct path');
like($url, qr/show=\{count\?\}/, 'correct path');
like($url, qr/lang=\{language\?\}/, 'correct path');
like($url, qr/p=\{startPage\?\}/, 'correct path');
like($url, qr/q=\{searchTerms\}/, 'correct path');

my $result_rss = app->endpoint($url => { searchTerms => 'balloon', '?' => undef });
like($result_rss, qr/q=balloon/, 'Correct searchTerms');
like($result_rss, qr/format=rss/, 'Correct searchTerms');

$t->get_ok($result_rss)
  ->text_is('totalResults', 1)
  ->text_is('startIndex', 0)
  ->text_is('itemsPerPage', 25)
  ->text_is('title', 'My Search')
  ->text_is('description', 'Search my site')
  ->text_is('item title', 'My second Balloon')
  ->text_like('item link', qr/page2$/)
  ->text_is('item description', 'Thanks for searching my balloon');

$t->get_ok($result_atom)
  ->text_is('totalResults', 1)
  ->text_is('startIndex', 0)
  ->text_is('itemsPerPage', 25)
  ->text_is('title', 'My Search')
  ->text_is('entry title', 'My second Balloon')
  ->text_is('content[type=text]', 'Thanks for searching my balloon');

done_testing;
