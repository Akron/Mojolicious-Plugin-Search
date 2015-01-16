package Mojolicious::Plugin::Search::Lucy::lucy;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw/GetOptions :config no_auto_abbrev no_ignore_case/;

has description => 'Manage your Lucy index.';
has usage       => sub { shift->extract_usage };

# Run chi
sub run {
  my $self = shift;

  my $command = shift;

  print $self->usage and return unless $command;

  # Get the application
  my $app = $self->app;
  my $log = $app->log;

  # List all associated caches
  if ($command eq 'optimize') {

    my $i = $app->search->new_indexer;

    if ($i) {
      $i->optimize;
      print "Index successfully optimized!\n";
      return 1;
    }
    else {
      print "Unable to open index!\n";
    };
  };

  # Unknown command
  print $self->usage and return;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Lucy::lucy - Manage your Lucy Index


=head1 SYNOPSIS

  usage: perl app.pl lucy <command>

    perl app.pl lucy optimize

  Interact with Lucy indices associated with your application.
  Valid commands include:

    optimize
      Optimize your index for search performance.
      Warning: This may take some time!


=head1 DESCRIPTION

L<Mojolicious::Plugin::Search::Lucy::lucy> helps you to manage your
Lucy index associated with L<Mojolicious::Plugin::Search>.


=head1 ATTRIBUTES

L<Mojolicious::Plugin::Search::Lucy::lucy> inherits all attributes
from L<Mojolicious::Command> and implements the following new ones.


=head2 description

  my $description = $lucy->description;
  $lucy = $lucy->description('Foo!');

Short description of this command, used for the command list.


=head2 usage

  my $usage = $lucy->usage;
  $lucy = $lucy->usage('Foo!');

Usage information for this command, used for the help screen.


=head1 METHODS

L<Mojolicious::Plugin::Search::Lucy::lucy> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.


=head2 run

  $lucy->run;

Run this command.


=head1 DEPENDENCIES

L<Mojolicious>,
L<Lucy>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Search


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015, L<Nils Diewald||http://nils-diewald.de>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

The documentation is based on L<Mojolicious::Command::eval>,
written by Sebastian Riedel.

=cut
