#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use Mojo::ByteStream 'b';
use lib '../lib';
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
    my $mojo = shift;
    $mojo->log->info('Initial indexing');
    my $path = $mojo->home . '/sample';

    opendir(SAMPLE, $path);
    my @docs;
    foreach my $filename (readdir(SAMPLE)) {
      if ($filename =~ /\.txt$/) {
	my $text = b($path . '/' . $filename)->slurp;
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

    $mojo->lucy->add( @docs );
  }
  # truncate => 1,
  # language => 'de',
  # highlighter => {
  #   excerpt_length => 200,
  #   pre_tag => '<span class="match">',
  #   post_tag => '</span>'
  # }
  # fields => {},
  # on_init => sub {},
};

get '/' => sub {
  my $c = shift;
  my $query = $c->param('q');
  my $template =<< 'TEMPLATE';
<!DOCTYPE html>
<html>
  <head><title><%= stash 'search.query' %></title></head>
  <body>
%= search highlight => 'content', begin
<p>Hits: <span id="count"><%= stash 'search.totalResults' %></span></p>
%=   search_hits begin
<div>
  <h1><a href="<%= $_->{url} %>"><%= $_->{title} %></a></h1>
  <p class="excerpt"><%= lucy_snippet %></p>
  <p class="score"><%= $_->get_score %></p>
</div>
%   end
% end
  </body>
</html>
TEMPLATE

  return $c->render(
    inline => $template,
    'search.query'      => scalar $c->param('q'),
    'search.startPage'  => scalar $c->param('page'),
    'search.count'      => scalar $c->param('count')
  );
};

my $t = Test::Mojo->new;

$t->get_ok('/?q=test')
  ->text_is('head title', 'test')
  ->text_is('#count', 1)
  ->text_is('h1 a', 'Article VI')
  ->element_exists('h1 a[href=/text/art6.txt]')
  ->text_like('p.excerpt', qr/Office/);

$t->get_ok('/?q=the')
  ->text_is('head title', 'the')
  ->text_is('#count', 51)
  ->element_exists('h1 a[href=/text/amend10.txt]')
  ->text_like('p.excerpt span.match', qr/^the$/i);

done_testing;

__END__
