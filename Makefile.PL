#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Search',
  AUTHOR       => 'Nils Diewald',
  ABSTRACT     => 'Search Engines for Mojolicious',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Search.pm',
  BUILD_REQUIRES => {
    'Test::More' => 0,
    'File::Temp' => 0
  },
  PREREQ_PM => {
    'Mojolicious' => 7.15,
    'Mojolicious::Plugin::Util::Endpoint' => 0.19,
    'Lucy' => '0.006001'
  },
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    requires  => { perl => '5.010001' },
    resources => {
      license     => 'http://www.opensource.org/licenses/artistic-license-2.0',
      repository  => 'https://github.com/Akron/Mojolicious-Plugin-Search'
    }
  },
  MIN_PERL_VERSION => '5.010001',
  test => {TESTS => 't/*.t'}
);
