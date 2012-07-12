#### -*- mode: CPerl; -*-
#### File name:     AddressMap.pm
#### Description:   IPAM::AddressMap class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id:$

package IPAM::AddressMap;
use IPAM::Thing;
use IPAM::Prefix;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::AddressMap - Class that describe an address map

=head1 SYNOPSIS

use IPAM::AddressMap;

=head1 DESCRIPTION

The IPAM::AddressMap class is derived from IPAM::Thing.  It stores a
hierarchy of L<IPAM::Prefix> objects.  Its purpose is to represent an
organization's addressing plan from high-level functional blocks down
to IP subnets (also called "stub nets").

=cut

sub new($$$$) {
  my ($class, $node, $name) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{prefix_r} = IPAM::Prefix::Registry->new();
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item lookup_by_ip($ip)

my $prefix = $address_map->lookup_by_ip($ip);
my ($prefix, @path) = $address_map->lookup_by_ip($ip);

If called in a scalar context, returns the uniqe IPAM::Prefix object
that matches the NetAddr::IP object $ip or undef if no match is found.
If called in a list context, it also returns the list of IPAM::Prefix
objects that were traversed during the search.  The last element of
this list is the most specific covering prefix of $ip.  The following
code covers alle possible cases

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

=item lookup_by_id($id)

my @prefixes = $address_map->lookup_by_id($id);

Returns a list of IPAM::Prefix objects whose id attribute matches the
string $id.  The id attribute is derived from the "name" attribute of
a <block> or <net> XML element in the IPAM database.  Note that the
name of an IPAM::Prefix as returned by the name() instance method
inherited from the IPAM::Thing class is, by convention, the
human-readable CIDR representation of the prefix.  While the former is
unique in the address map, the latter is not.

=cut

sub lookup_by_id($$$) {
  my ($self, $name, $stub_only) = @_;
  return($self->{prefix_r}->lookup_by_id($name, $stub_only));
}

=item registry()

my $registry = $address_map->registry()

Returns the IPAM::Prefix::Registry object associated with the address
map.

=back

=cut

sub registry($) {
  my ($self) = @_;
  return($self->{prefix_r})
}

1;
