#### -*- mode: CPerl; -*-
#### File name:     Network.pm
#### Description:   IPAM::Network class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Network.pm,v 1.6 2012/09/04 13:19:10 gall Exp gall $

package IPAM::Network;
use IPAM::Thing;
use IPAM::Prefix;
use IPAM::Host;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Network - Class that describes an IP subnet

=head1 SYNOPSIS

  use IPAM::Network;

=head1 DESCRIPTION

The L<IPAM::Network> class is derived from L<IPAM::Thing>.  It stores
all information associated with an IP subnet, i.e. a network that
contains hosts.  A network is associated with at most one IPv4 and any
number of IPv6 stub networks but at least one of either type (this is
not enforced by the network object but should be enforced by the IPAM
parser).  These prefixes are stored in a L<IPAM::Prefix::Registry>.
It also contains a L<IPAM::Host::Registry> that collects all hosts
that have been defined in the context of the network.  It may also be
associated with a geographic location that will be published as DNS
LOC records for the hosts.

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $name, $location)>

  my $net = IPAM::Network->new($node, $name, $loc);

Creates a new instance and associates a geographic location in the
form of a DNS LOC record with it.  Note that the location is not
checked to be in valid DNS master file syntax.

=back

=cut

sub new($$$) {
  my ($class, $node, $name, $location) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{location} = $location;
  $self->{prefix_r} = IPAM::Prefix::Registry->new();
  $self->{host_r} = IPAM::Host::Registry->new();
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<location()>

  my $loc = $net->location();

Returns the location string that was passed to the C<new()> method.

=cut

sub location($) {
  my ($self) = @_;
  return($self->{location});
}

=item C<add_prefix($prefix)>

  eval { $net->add_prefix($prefix) } or die $@;

Adds the given L<IPAM::Prefix> object to the registry of prefixes
associated with the network.  An exception is raised if this fails
(see L<IPAM::Prefix>).

=cut

sub add_prefix($$) {
  my ($self, $prefix) = @_;
  $self->{prefix_r}->add($prefix);
}

=item C<prefixes($sorter, $af)>

  my @prefixes = $net->prefixes();
  my @prefixes = $net->prefixes(undef, '6');
  my @prefixes = $net->prefixes(sub { my ($a, $b) = @_;
                                    $a->ip() cmp $b->ip() });

Returns a list of objects in the network's L<IPAM::Prefix::Registry>
of the given address family or for all address families if C<$af> is
not defined.  A sorting method can be supplied as for the
L<IPAM::Registry> methods C<things()> and C<iterator()>.

=cut

sub prefixes($$$) {
  my ($self, $sorter, $af) = @_;
  return($self->{prefix_r}->things($sorter, $af));
}

=item C<prefix_registry()>

  my $registry = $net->prefix_registry();

Returns the network's L<IPAM::Prefix::Registry>.

=cut

sub prefix_registry($) {
  my ($self) = @_;
  return($self->{prefix_r});
}

=item C<add_address($address)>

  eval { $net->add_address($address) } or die $@;

Adds the L<IPAM::Address> object C<$address> to the network's prefix
by which it is covered.  An exception is raised if the address is not
covered by any prefix associated with the network.  Note that this
address will be part of the address map.

=cut

sub add_address($$) {
  my ($self, $address) = @_;

  foreach my $prefix ($self->prefixes(undef, $address->af())) {
    $prefix->contains($address) and return($prefix->add($address));
  }
  die "Address ".$address->name()." not covered by any prefix of network "
    .$self->name()." (" .join(', ', map { $_->name() }
			      $self->prefixes(undef, $address->af())).")\n";
}

=item C<find_address($ip)>

  my $address = $net->find_address($ip);

Searches the L<IPAM::Prefix::Registry> for an L<IPAM::Address> object
that matches the given L<NetAddr::IP> object C<$ip>.  Returns the
object or undef if no match is found.

=cut

sub find_address($$) {
  my ($self, $ip) = @_;
  return($self->{prefix_r}->lookup_by_ip($ip));
}

=item C<add_host($host)>

  eval { $net->add_host($host) } or die $@;

Adds the given L<IPAM::Host> object to the network's host registry.
An execption is raised if a host with the same name has already been
registered.

=cut

sub add_host($$) {
  my ($self, $host) = @_;
  $self->{host_r}->add($host);
}

=item C<find_host($fqdn)>

  my $host = $net->find_host($fqdn);

Searches the network's L<IPAM::Host::Registry> for an object that
matches the given C<$fqdn>.  Returns that object or false if not
found.

=cut

sub find_host($$) {
  my ($self, $fqdn) = @_;
  return($self->{host_r}->lookup($fqdn));
}

=item C<hosts()>

  my @hosts = $net->hosts();

Returns a list of objects in the network's L<IPAM::Host::Registry>.

=cut

sub hosts($) {
  my ($self) = @_;
  return($self->{host_r}->things());
}

=item C<host_registry()>

  my $registry = $net->host_registry();

Returns the network's L<IPAM::Host::Registry>.

=cut

sub host_registry($) {
  my ($self) = @_;
  return($self->{host_r});
}

=item C<find_alias($fqdn)>

  my $alias = $net->find_alias($fqdn);

Searches the registries of aliases of all hosts in the network for the
FQDN C<$fqdn> and returns the L<IPAM::Host> object of the canonical
name or undef if no matching alias is found.  Note that an alias can
have at most one canonical name.

=cut

sub find_alias($$) {
  my ($self, $fqdn) = @_;
  my @result;
  map { push(@result, $_) if $_->alias_registry()->lookup($fqdn) }
    $self->{host_r}->things();
  return(@result);
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Prefix>, L<IPAM::Address>, L<NetAddr::IP>

=cut

package IPAM::Network::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Network registry';

=head1 NAME

IPAM::Network::Registry - Class of a registry for L<IPAM::Network> objects

=head1 SYNOPSIS

  use IPAM::Network;

=head1 DESCRIPTION

The L<IPAM::Network::Registry> class is derived from
L<IPAM::Registry>.  It stores a list of L<IPAM::Network> objects.

=head1 INSTANCE METHODS

=over 4

=item C<find_host($fqdn)>

  my @hosts = $net_r->find_host($fqdn);

Calls the C<find_host()> method of all L<IPAM::Network> objects in the
registry and returns the list of matching L<IPAM::Host> objects.

=cut

sub find_host($$) {
  my ($self, $fqdn) = @_;
  my @result;
  my $next = $self->iterator();
  while (my $network = $next->()) {
    push(@result, $network->find_host($fqdn));
  }
  return(@result);
}

=item C<find_alias($fqdn)>

  my @aliases = $net_r->find_alias($fqdn);

Calls the C<find_alias()> method of all L<IPAM::Network> objects in
the registry and returns the L<IPAM::Host> object of the alias'
canonical name or undef if such alias exists.

=cut

sub find_alias($$) {
  my ($self, $fqdn) = @_;
  my @result;
  map { push(@result, $_->find_alias($fqdn)) } $self->things();
  return(@result);
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<IPAM::Network>

=cut

1;
