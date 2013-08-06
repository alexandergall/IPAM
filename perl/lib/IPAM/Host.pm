#### -*- mode: CPerl; -*-
#### File name:     Host.pm
#### Description:   IPAM::Host class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Host.pm,v 1.3 2013/02/06 13:30:42 gall Exp gall $

package IPAM::Host;
use IPAM::Thing;
use IPAM::Registry;
use IPAM::Address;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Host - Class that describes a canonical host

=head1 SYNOPSIS

use IPAM::Host;

=head1 DESCRIPTION

The L<IPAM::Host> class is derived from L<IPAM::Thing>.  It stores
information about a canonical host, i.e. a host that is associated
with IP addresses whose reverse DNS mappings point to the name of the
host.  An L<IPAM::Host> knows to which L<IPAM::Network> it belongs and
which names are used for aliases and secondary address records.

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $name, $network)>

  my $host = IPAM::Host->new($node, $name, $network);

Creates an instance of a host and associates the L<IPAM::Network>
object $network with it.

=cut

=back

=cut

sub new($$$) {
  my ($class, $node, $name, $network) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{network} = $network;
  $self->{dns} = 1;
  $self->{address_r} = IPAM::Address::Registry->new();
  $self->{alias_r} = IPAM::Registry->new();
  $self->{hosted_on_r} = IPAM::Registry->new();
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<dns($state)>

  my $dns_state = $host->dns();
  $host->dns(0);

If $state is defined, it is treated as a boolean value and the flag
whether DNS information should be generated for the host or not is set
accordingly.  The value of $state is returned unaltered.  If $state is not defined, the current value is returned.

=cut

sub dns($$) {
  my ($self, $value) = @_;
  defined $value and $self->{dns} = $value;
  return($self->{dns});
}

=item C<network()>

  my $network = $host->network();

Returns the L<IPAM::Network> object with which the host is associated.

=cut

sub network($) {
  my ($self) = @_;
  return($self->{network});
}

=item C<add_address($address)>

  eval { $host->add_address($address) } or die $@;

Adds the L<IPAM::Address> object $address to the host's address
registry.  An exception is raised if the address is already registered
for the host.

=cut

sub add_address($$) {
  my ($self, $address) = @_;
  $self->{address_r}->add($address);
}

=item C<addresses($sorter, $af)>

  my @addresses = $host->addresses();
  my @addresses = $host->addresses(undef, '6');
  my @addresses = $host->addresses(sub { my ($a, $b) = @_;
                                         $a->ip() cmp $b->ip()});

Returns the list of L<IPAM::Address> objects of the given address
family (or all address families if $af is not defined) that are
associated with the host.  A sorting method can be supplied as for the
L<IPAM::Registry> methods things() and iterator().

=cut

sub addresses($$$) {
  my ($self, $sorter, $af) = @_;
  return($self->{address_r}->things($sorter, $af));
}

=item C<address_registry()>

  my $registry = $host->address_registry();

Returns the L<IPAM::Address::Registry> object of the host.

=cut

sub address_registry($) {
  my ($self) = @_;
  return($self->{address_r});
}

=item C<add_alias($alias)>

  eval { $host->add_alias($alias) } or die $@;

Adds the L<IPAM::Thing> object $alias to the host's alias registry.
Such a reference will create a DNS CNAME record for the name
associated wiht the alias pointing to the name of the host.  An
exception is raised if an alias of the same name has already been
registered.

=cut

sub add_alias($$) {
  my ($self, $alias) = @_;
  $self->{alias_r}->add($alias);
}

=item C<aliases($sorter)>

  my @aliases = $host->aliases();

Returns the list of L<IPAM::Thing> objects in the host's "alias"
registry.  An optional anonymous subroutine C<$sorter> will be passed
to the C<things()> method of the alias registry.

=cut

sub aliases($$) {
  my ($self, $sorter) = @_;
  return($self->{alias_r}->things($sorter));
}

=item C<alias_registry()>

  my $registry = $host->alias_registry();

Returns the L<IPAM::Registry> associated with the "alias" registry of
the host.

=cut

sub alias_registry($) {
  my ($self) = @_;
  return($self->{alias_r});
}

=item C<add_hosted_on($hosted_on)>

   eval { $host->add_hosted_on($hosted_on) } or die $@;

Adds the L<IPAM::Thing> object $hosted_on to the host's "hosted-on"
registry.  Such a reference will create a PTR record for the host
pointing to the name associated with $hosted_on.  This is mainly used
by the cavari filter generator to associate an address with the host
on which the firewall rules for the host need to be installed.  An
exception is raised if an alias of the same name has already been
registered.

=cut

sub add_hosted_on($$) {
  my ($self, $hosted_on) = @_;
  $self->{hosted_on_r}->add($hosted_on);
}

=item C<hosted_on()>

  my @aliases = $host->hosted_on();

Returns the list of L<IPAM::Thing> objects in the host's "hosted-on" registry.

=cut

sub hosted_on($) {
  my ($self) = @_;
  return($self->{hosted_on_r}->things());
}

=item C<hosted_on_registry()>

  my $registry = $host->hosted_on_registry();

Returns the L<IPAM::Registry> associated with the "hosted-on" registry
of the host.

=cut

sub hosted_on_registry($) {
  my ($self) = @_;
  return($self->{hosted_on_r});
}

#### Registry for IPAM::Host objects
package IPAM::Host::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Host registry';

1;
