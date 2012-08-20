#### -*- mode: CPerl; -*-
#### File name:     Address.pm
#### Description:   IPAM::Address class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Address.pm,v 1.1 2012/07/12 08:08:43 gall Exp gall $

package IPAM::Address;
use IPAM::Prefix;
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

The name of the object as returned by the name() instance method does
not contain the prefix length (i.e. the maximum prefix length is
implied).

=head1 EXTENDED CLASS METHODS

=over 4

=item new($node, $addr, $reserved)

my $address = eval { IPAM::Address->new($node, $addr) } or die $@;

Creates an instance from $addr just like the base method but raises an
exception if the prefix length is not equal to the maximum allowed for
the address family.  The name is set to the output of the addr()
instance method of the L<NetAddr::IP> class.  The address is not yet
associated with a canonical host.  If $reserved is a true value, the
id is set to the string 'RESERVED', otherwise it is set to the string
'<no canonical name>'.

=back

=cut

sub new($$$$) {
  my ($class, $node, $address, $reserved) = @_;
  my $self = $class->SUPER::new($node, $address,
				$reserved ? '<RESERVED>' :
				'<no canonical name>',
				undef);

  ## The Prefix constructor adds the prefix length to the name.  We
  ## don't want this for addresses.
  $self->{name} = $self->{ip}->addr();
  $self->{canonical} = undef;
  $self->{host_r} = IPAM::Host::Registry->new();
  $self->ip()->masklen() == $IPAM::af_info{$self->ip()->version()}{max_plen} or
    die "Prefix ".$self->name()." found where address expected\n";
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item canonical_host()

my $host = $address->canonical_host();

Returns the L<IPAM::Host> object of the canonical host associated with
the address.

=item canonical_host($host)

$address->canonical_host($host);

Sets the L<IPAM::Host> object $host to be the canonical host
associated with the address.

=cut

sub canonical_host($$) {
  my ($self, $host) = @_;
  if (defined $host) {
    if ($self->{canonical}) {
      my ($file, $line) = $self->{canonical}->nodeinfo();
      die "Can't set ".$host->name()." as canonical host for "
	.$self->name()." (already assigned to ".$self->{canonical}->name()
	  ." at $file, $line)\n";
    }
    $self->{canonical} = $host;
    $self->{id} = $host->name();
  }
  return($self->{canonical});
}

=item add_host($host)

$address->add_host($host);

Adds the L<IPAM::Host> object to the addresse's
L<IPAM::Host::Registry>.

=cut

sub add_host($$) {
  my ($self, $host) = @_;
  $self->{host_r}->add($host);
}

=item hosts()

my @hosts = $address->hosts();

Returns the list of L<IPAM::Host> objects in the addresse's registry
of hosts that are assigned to the $address.

=back

=cut

sub hosts($) {
  my ($self) = @_;
  return($self->{host_r}->things());
}

#### Registry for IPAM::Address objects.
package IPAM::Address::Registry;
our @ISA = qw(IPAM::Prefix::Registry);
our $name = 'Address registry';

1;
