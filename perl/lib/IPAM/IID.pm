#### -*- mode: CPerl; -*-
#### File name:     IID.pm
#### Description:   IPAM::IID class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: IID.pm,v 1.2 2012/07/24 08:39:18 gall Exp gall $

package IPAM::IID;
our @ISA = qw(IPAM::Thing);
my $zero_subnet_v6 = NetAddr::IP->new6('::/64');

=head1 NAME

IPAM::IID - Class that describes a canonical host

=head1 SYNOPSIS

use IPAM::IID;

=head1 DESCRIPTION

The L<IPAM::IID> class is derived from L<IPAM::Thing>.  It stores a
particular IID-to-host mapping.

=head1 EXTENDED CLASS METHODS

=over 4

=item new($node, $name, $id)

my $iid = eval { IPAM::IID->new($node, $name, $id) } or die $@;

The IID $id must be in the form of a IPv6 address and be part of ::/64.
An exception is raised if these conditions are not met.

=back

=cut

sub new($$$$) {
  my ($class, $node, $name, $id) = @_;
  $id =~ s/^\s+//;
  $id =~ s/\s+$//;
  my $self = $class->SUPER::new($node, $name);
  $self->{ip} = NetAddr::IP->new6($id) or
    die "$self->{name}: Malformed IPv6 address $id\n";
  $self->{ip}->within($zero_subnet_v6) or
    die "$self->{name}: IID $id not within ::/64\n";
  $self->{in_use} = 0;
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item ip()

my $ip = $iid->ip();

Returns the L<NetAddr::IP> object that represents the IID.

=cut

sub ip {
  my ($self) = @_;
  return($self->{ip});
}

=item in_use($use)

Marks the IID as in use if $use is a true value.

=item in_use()

Returns true if the IID is in use, i.e. if it is referenced at least
once from a <ipv6> address assignment via the "from-iid" attribute.

=back

=cut

sub in_use($use) {
  my ($self, $use) = @_;
  defined $use and $self->{in_use} = $use;
  return($self->{in_use});
}

package IPAM::IID::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'IID registry';

=head1 NAME

IPAM::IID::Registry - Class of a registry for L<IPAM::IID> objects

=head1 SYNOPSIS

use IPAM::IID;

=head1 DESCRIPTION

The L<IPAM::IID> class is derived from L<IPAM::Registry>.  It stores a
list of IIDs represented as L<IPAM::IID> objects.

=head1 EXTENDED INSTANCE METHODS

=over 4

=item add($iid)

eval { $iid_r->add($iid_new) } or die $@;

Adds the L<IPAM::IID> object $iid_new to the list IIDs.  An exception is
raised if a mapping for the same IID already exists.

=cut

sub add($$$) {
  my ($self, $iid_new) = @_;

  ## Check for uniqueness of IID
  my $id_new = $iid_new->ip->addr();
  my $next_iid = $self->iterator();
  while (my $iid = $next_iid->()) {
    if ($id_new eq $iid->ip()->addr()) {
      my ($file, $line) = IPAM::_nodeinfo($iid->node());
      die "$self->{name}: Duplicate definition of $id_new "
	."(previous definition at $file, $line)\n";
    }
  }
  $self->SUPER::add($iid_new);
}

=item lookup_by_ip($ip)

my $iid = $iid_r->lookup_by_ip($ip);

Searches the registry for the IID represented by the L<NetAddr::IP>
object $ip and returns the corresponding L<IPAM::IID> object or undef
if no match is found.

=back

=cut

sub lookup_by_ip($$) {
  my ($self, $ip) = @_;
  $ip->version() == 6 or return(undef);
  my $next_iid = $self->iterator();
  while (my $iid = $next_iid->()) {
    $ip == $iid->ip() and return($iid);
  }
  return(undef);
}

1;
