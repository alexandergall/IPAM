#### -*- mode: CPerl; -*-
#### File name:     Thing.pm
#### Description:   IPAM::Thing class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Thing.pm,v 1.4 2012/09/03 12:22:55 gall Exp gall $
package IPAM::Thing;

=head1 NAME

IPAM::Thing - Base class for named Things

=head1 SYNOPSIS

use IPAM::Thing;

=head1 DESCRIPTION

L<IPAM::Thing> is the base class for all objects stored in the IPAM.
A basic Thing has three properties.

=over 4

=item Name

This is an arbitrary string that identifies the Thing.  If the Thing
is part of a L<IPAM::Registry>, the name converted to lower-case will
be unique within the registry.

=item Node

Most Things in the IPAM are derived from an XML element in the IPAM
database.  In this case, the node attribute of a Thing is a reference
to the L<XML::LibXML::Node> object from which it was constructed.

=item Description

The description is a free-form text field that may contain a
human-readable description of the Thing.  When a Thing is created, the
description is initialized to an empty string.

=back

=head1 CLASS METHODS

=over 4

=item new($node, $name)

my $thing = IPAM::Thing->new($node, $name);

Creates a new thing called $name and associates the
L<XML::LibXML::Node> object $node with it, which may be undefined if
the thing is not associated with any XML node in the IPAM database.

=back

=cut

sub new($$$) {
  my ($class, $node, $name) = @_;
  my $self = { node => $node, name => $name, description => '' };
  return(bless($self, $class));
}

=head1 INSTANCE METHODS

=over 4

=item name()

my $name = $thing->name();

Returns the Thing's name.

=cut

sub name($) {
  my ($self) = @_;
  return($self->{name});
}

=item node()

my $node = $thing->node();

Returns a reference to the L<XML::LibXML::Node> object associated with
the Thing.

=cut

sub node($) {
  my ($self) = @_;
  return($self->{node});
}

=item nodeifno()

my ($file, $line) = $thing->nodeinfo();

Returns the file name and line number where the XML node associated
with the Thing is defined or undef if no node is associated with the
Thing.

=cut

sub nodeinfo($) {
  my ($self) = @_;
  return(IPAM::_nodeinfo($self->{node}));
}

=item description()

my $description = $thing->description();

Returns a string that contains free-form text describing the Thing.

=item description($descr)

$thing->description('Foo bar baz');

Registers the free-from text $descr as a description of the Thing.

=cut

sub description($$) {
  my ($self, $description) = @_;
  if (defined $description) {
    $self->{description} = $description;
  }
  return($self->{description});
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<XML::LibXML>

=cut

1;
