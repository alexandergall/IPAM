#### -*- mode: CPerl; -*-
#### File name:     AddressMap.pm
#### Description:   IPAM::AddressMap class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: AddressMap.pm,v 1.1 2012/07/12 08:08:43 gall Exp gall $

package IPAM::AddressMap;
use IPAM::Thing;
use IPAM::Prefix;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::AddressMap - Class that describe an address map

=head1 SYNOPSIS

  use IPAM::AddressMap;

=head1 DESCRIPTION

The L<IPAM::AddressMap> class is derived from L<IPAM::Thing>.  It
holds a L<IPAM::Prefix::Registry>, storing a hierarchy of
L<IPAM::Prefix> objects that represent an organization's addressing
plan from high-level functional blocks down to IP subnets provided by
the <address-map> element of an IPAM database.  It provides a facility
to search the registry by prefix or C<id> (a non-unique identifier in
the form of a DNS FQDN).

=cut

sub new($$$$) {
  my ($class, $node, $name) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{prefix_r} = IPAM::Prefix::Registry->new();
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<lookup_by_ip($ip)>

  my $prefix = $address_map->lookup_by_ip($ip);
  my ($prefix, @path) = $address_map->lookup_by_ip($ip);

This method traverses the prefix registry recursively, looking for a
L<IPAM::Prefix> object whose associated L<NetAddr::IP> object (as
returned by its C<ip()> method) matches the supplied L<NetAddr::IP>
object C<$ip>.  If called in a scalar context, it returns the
L<IPAM::Prefix> or undef if no match is found.  If called in a list
context, it also returns the list of L<IPAM::Prefix> objects that were
traversed during the search.  The last element of this list is the
most specific covering prefix of C<$ip>.  The following code covers
alle possible cases

  my ($prefix, @path) = $address_map->lookup_by_ip($ip);
  unless ($prefix or @path) {
    print "Not covered by address map\n";
  } elsif ($prefix) {
    print "Exact match\n";
  } else {
    print "No exact match, closest covering prefix "
      .pop(@path)->name()."\n"
  }

=cut

sub lookup_by_ip($$) {
  my ($self, $ip) = @_;
  if (wantarray()) {
    (return($self->{prefix_r}->lookup_by_ip($ip)));
  } else {
    return($self->{prefix_r}->lookup_by_ip($ip));
  }
}

=item C<lookup_by_id($id)>

  my @prefixes = $address_map->lookup_by_id($id);

Returns a list of L<IPAM::Prefix> objects whose C<id> attribute
matches the string C<$id>.  The C<id> attribute is derived from the
C<name> attribute of a C<< <block> >> or C<< <net> >> XML element in
the IPAM database.  Note that the name of an L<IPAM::Prefix> as
returned by the C<name()> instance method inherited from the
L<IPAM::Thing> class is, by convention, the human-readable CIDR
representation of the prefix.  While the former is unique in the
address map, the latter is not.

=cut

sub lookup_by_id($$$) {
  my ($self, $name, $stub_only) = @_;
  return($self->{prefix_r}->lookup_by_id($name, $stub_only));
}

=item C<registry()>

  my $registry = $address_map->registry()

Returns the L<IPAM::Prefix::Registry> object associated with the
address map.

=cut

sub registry($) {
  my ($self) = @_;
  return($self->{prefix_r})
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Prefix>, L<IPAM::Prefix::Registry>

=cut

1;
