#### -*- mode: CPerl; -*-
#### File name:     Address.pm
#### Description:   IPAM::Address class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012

package IPAM::Address;
use IPAM::Prefix;
use IPAM::Host;
our @ISA = qw(IPAM::Prefix);

=head1 NAME

IPAM::Address - Class that describes a network address

=head1 SYNOPSIS

  use IPAM::Address;

=head1 DESCRIPTION

The L<IPAM::Address> class is derived from L<IPAM::Prefix>.  The
derived class limits the prefix length to the maximum allowed by the
address family.  An address is associated with any number of
L<IPAM::Host> objects which are using the address.  At most one
L<IPAM::Host> object is designated to be the canonical name for the
address.

The name of the object as returned by the C<name()> instance method
does not contain the prefix length (i.e. the maximum prefix length is
implied).

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $addr, $reserved)>

  my $address = eval { IPAM::Address->new($node, $addr, $reserved) } or die $@;

Creates an instance from $addr just like the base method but raises an
exception if the prefix length is not equal to the maximum allowed for
the address family.  The name is set to the output of the C<addr()>
instance method of the L<NetAddr::IP> class.  The address is not yet
associated with a canonical host.  If C<$reserved> is a true value,
the address is marked as being reserved.  A reserved address will be
registered in the corresponding subnet but cannot be assigned to a
host.

=cut

sub new($$$) {
  my ($class, $node, $address, $reserved) = @_;
  my $self = $class->SUPER::new($node, $address, undef, undef);

  ## The Prefix constructor adds the prefix length to the name.  We
  ## don't want this for addresses.
  $self->{name} = $self->{ip}->addr();
  $self->{canonical} = undef;
  $self->{reserved} = $reserved;
  $self->{host_r} = IPAM::Host::Registry->new();
  $self->ip()->masklen() == $IPAM::af_info{$self->ip()->version()}{max_plen} or
    die "Prefix ".$self->name()." found where address expected\n";
  return($self);
}

=item C<id()>

  my $id = $address->id();

Calls the base method unless the address is marked as reserved or has
no canonical host.  If the address is reserved (C<<
$address->reserved() >> returns a true value), the string '<RESERVED>'
is reserved.  If the address has no canonical name, the string '<no
canonical name>' is returned.

=cut

sub id($) {
  my ($self) = @_;
  $self->{reserved} and return('<RESERVED>');
  $self->{canonical} or return('<no canonical name>');
  return($self->SUPER::id());
}

=back

=head1 INSTANCE METHODS

=over 4

=item C<is_reserved()>

  if ($address->is_reserved()) {
    print $address->name()." is reserved.\n";
  }

Returns true if the address is marked as reserved, false otherwise.

=cut

sub is_reserved($) {
  my ($self) = @_;
  return($self->{reserved});
}

=item C<canonical_host()>

  my $host = $address->canonical_host();

Returns the L<IPAM::Host> object of the canonical host associated with
the address or undef if the address doesn't have a canonical host.

=item C<canonical_host($host)>

  eval { $address->canonical_host($host) } or die $@;

Sets the L<IPAM::Host> object C<$host> to be the canonical host of the
address. The C<id> attribute of the address is set to the hostname as
obtained from the host's C<name()> method. In addition, the address'
C<description> attribute is copied from the host's description.

An exception is raised if a canonical name has already been set or if
the address is marked as reserved.

=cut

sub canonical_host($$) {
  my ($self, $host) = @_;
  if (defined $host) {
    if ($self->{canonical}) {
      my ($file, $line) = $self->{canonical}->nodeinfo();
      die "Can't set ".$host->name()." as canonical host for "
	.$self->name().": already assigned to ".$self->{canonical}->name()
	  ." at $file, $line\n";
    }
    $self->{reserved} and
      die "Can't set ".$host->name()." as canonical host for "
	.$self->name().": marked as reserved\n";
    $self->{canonical} = $host;
    $self->{id} = $host->name();
    $self->description($host->description());
  }
  return($self->{canonical});
}

=item C<add_host($host)>

  $address->add_host($host);

Adds the L<IPAM::Host> object C<$host> to the addresse's
L<IPAM::Host::Registry>.

=cut

sub add_host($$) {
  my ($self, $host) = @_;
  $self->{host_r}->add($host);
}

=item C<hosts()>

  my @hosts = $address->hosts();

Returns the list of L<IPAM::Host> objects in the addresse's registry
of hosts.

=cut

sub hosts($) {
  my ($self) = @_;
  return($self->{host_r}->things());
}

=item C<registry()>

  my $reg = $address->registry();

Returns the L<IPAM::Host::Registry> that stores all L<IPAM::Host>
objects to which the address is assigned.

=cut

sub registry($) {
  my ($self) = @_;
  return($self->{host_r});
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Prefix>, L<IPAM::Host>, L<IPAM::Network>

=cut

#### Registry for IPAM::Address objects.
package IPAM::Address::Registry;
our @ISA = qw(IPAM::Prefix::Registry);
our $name = 'Address registry';

1;
