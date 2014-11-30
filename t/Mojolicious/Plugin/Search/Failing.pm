package Mojolicious::Plugin::Search::Failing;
use Mojo::Base 'Mojolicious::Plugin';

# Engine missing a search method
sub register {};

1;
