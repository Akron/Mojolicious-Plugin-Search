#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use lib '../lib', 'lib', 't';

plugin Search => {
  engine => 'Failing'
};

get '/' => sub {
  my $c = shift;
  return $c->render(text => 'fine') unless $c->param('q');

  return $c->render(text => $c->search(
    q => 'yeah'
  ));
};

my $t = Test::Mojo->new;

$t->get_ok('/')
  ->content_is('fine');

$t->get_ok('/?q=test')
  ->text_like('#error', qr/method.+?search/);


done_testing;
