#### -*- mode: CPerl; -*-
#### File name:     Things.pm
#### Description:   IPAM::Thing class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id:$
package IPAM::Thing;

=head1 NAME

IPAM::Thing - Base class for named Things

=head1 SYNOPSIS

use IPAM::Thing;

=head1 DESCRIPTION

All items derived from an IPAM database are stored as IPAM::Thing
objects or derivatives thereof.  The only attributes of a plain Thing
are its name and optionally a reference to the L<XML::LibXML::Node>
object from which it was created.

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
  my $self = { node => $node, name => $name };
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

=back

=cut

sub nodeinfo($) {
  my ($self) = @_;
  return(IPAM::_nodeinfo($self->{node}));
}

1;
