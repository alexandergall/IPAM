#### -*- mode: CPerl; -*-
#### File name:     Prefix.pm
#### Description:   IPAM::Prefix class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Prefix.pm,v 1.6 2012/12/10 15:26:48 gall Exp gall $

package IPAM::Prefix;
use IPAM;
use IPAM::Address;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Prefix - Class that describes a network prefix

=head1 SYNOPSIS

  use IPAM::Prefix;

=head1 DESCRIPTION

The L<IPAM::Prefix> class is derived from L<IPAM::Thing>.  It
describes a network prefix which is represented by a L<NetAddr::IP>
object.  It also holds a L<IPAM::Prefix::Registry> that can store a
list of more-specific prefixes (which necessarily need to belong to
the same address family).

A prefix can be marked to be a "stub network".  In that case, it can
(but doesn't have to) be associated with a L<IPAM::Network> object.
The registry is then specialised to be of the type
L<IPAM::Address::Registry> and stores all addresses of hosts within
the prefix that belong to the stub network.

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $addr, $id, $stub)>

  my $prefix = eval { IPAM::Prefix->new($node, $addr, $id, $stub) } or die $@;

A L<NetAddr::IP> object is created from $addr, which is expected to be
a valid textual representation of a proper IP prefix, where "proper"
means that the host-part of the prefix (the bits of the address that
are covered by the zero-bits of the netmask) is zero.  For example,
2001:620:0:/48 is a proper prefix, but 2001:620:0:1::/48 is not.  

The name of the prefix object (as returned by the C<name()> instance
method) is set to the output of the C<cidr()> method of the prefixe's
L<NetAddr::IP> object.

C<$id> is a string by which the prefix can be found through the
C<lookup_by_id()> instance method of a L<IPAM::Prefix::Registry> in
which the prefix is stored.  The C<id> is a FQDN derived from the
C<name> attribute of the C<< <block> >> or C<< <net> >> XML element
which defines the prefix in the IPAM database.  Note that it does not
have to be unique.

C<$stub> is a boolean value that indicates whether the prefix
describes a stub network or not.

An exception is raised if C<$addr> cannot be interpreted as a proper
IP prefix of any known address family.

=back

=cut

sub new($$$$$) {
  my ($class, $node, $string, $id, $stub) = @_;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  my $ip = NetAddr::IP->new($string) or
    die "Malformed prefix or address: $string\n";
  $ip->network()->addr() eq $ip->addr() or
    die "Not a proper prefix (non-zero host part): $string\n";
  my $self = $class->SUPER::new($node, $ip->cidr());
  $self->{id} = $id;
  $self->{ip} = $ip;
  $self->{stub} = $stub;
  if ($stub) {
    $self->{prefix_r} = IPAM::Address::Registry->new();
  } else {
    $self->{prefix_r} = IPAM::Prefix::Registry->new();
  }
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<af()>

  my $af = $prefix->af();

Returns the address family of the prefix as returned by the
C<version()> instance method of the L<NetAddr::IP> object embedded in
the prefix.

=cut

sub af($) {
  my ($self) = @_;
  return($self->{ip}->version());
}

=item C<ip()>

  my $ip = $prefix->ip();

Returns the L<NetAddr::IP> object that represents the prefix.

=cut

sub ip($) {
  my ($self) = @_;
  return($self->{ip});
}

=item C<id()>

  my $id = $prefix->id();

Returns the C<id> attribute of the prefix.

=cut

sub id($) {
  my ($self) = @_;
  return($self->{id});
}

=item C<is_stub()>

  my $is_stub = $prefix->is_stub();

Returns true if the prefix represents a stub network, false otherwise.

=cut

sub is_stub($) {
  my ($self) = @_;
  return($self->{stub});
}

=item C<plen()>

  my $plen = $prefix->plen()

Returns the common prefix length of all sub-prefixes registered for
this prefix.  This represents the C<plen> attribute of the C<< <block>
>> element in the address map that defines the prefix.

=cut

=item C<plen($plen)>

  $prefix->plen($plen);

Sets the common prefix length for sub-prefixes of this prefix.  An
exception is raised if C<$plen>

=over 4

=item *

is not numeric

=item *

is less or equal than the prefix' own prefix length.

=item *

exceeds the maximum value for the prefix' address family.

=back

=cut

sub plen($$) {
  my ($self, $plen) = @_;
  my $max_plen = $IPAM::af_info{$self->af()}{max_plen};
  if (@_ > 1) {
    if (defined $plen) {
      $plen =~ /^\d+$/ or
	die "Can't set plen $plen for ".$self->name().": not numeric.\n";
      $plen <= $max_plen or
	die "Can't set plen $plen for ".$self->name()
	  .": larger than the maximum value $max_plen.\n";
      $plen > $self->ip()->masklen() or
	die "Can't set plen $plen for ".$self->name()
	  .": must be larger than the prefix length\n";
    }
    $self->{plen} = $plen;
    1;
  } else {
    return($self->{plen});
  }
}

=item C<network($network)>

  $prefix->network($network);

Associates the L<IPAM::Network> object C<$network> with the prefix.
Raises an exception if the prefix is not a stub network.

=item C<network()>

  my $net = $prefix->network();

Returns the L<IPAM::Network> object associated with the prefix.

=cut

sub network($$) {
  my ($self, $network) = @_;
  if (defined $network) {
    $self->is_stub() or die "Can't add network ".$network->name()
      ." to non-stub prefix ".$self->name()."\n";
    $self->{network} = $network;
  }
  return($self->{network});
}

=item C<contains($prefix)>

  if ($prefix->contains($other_prefix)) {
    print $other_prefix->name()." is a more specific prefix"
          ." prefix of ".$prefix->name()."\n";
  }

Returns true if the prefix strictly contains the given L<IPAM::Prefix>
object $prefix according to the C<contains()> method of the
L<NetAddr::IP> class, false otherwise.

=cut

sub contains($$) {
  my ($self, $prefix) = @_;
  return($self->{ip}->contains($prefix->ip()));
}

=item C<add($prefix)>

  eval { $prefix->add($other_prefix) } or die $@;

Adds the L<IPAM::Prefix> object C<$prefix> to the prefixe's own
L<IPAM::Prefix::Registry>.  An exception is raised if the address
families don't match or if C<$prefix> is not covered by the prefix or
if the prefix is a stub network and C<$prefix> is not an
L<IPAM::Address>.

=cut

sub add($$) {
  my ($self, $prefix) = @_;
  $self->af() == $prefix->af()
    or die "Can't add ".$prefix->name()." to prefix ".$self->name()
      .": address family mismatch\n";
  ($self->contains($prefix) and $self->{ip} != $prefix->ip())
    or die "Can't add ".$prefix->name()." to ".$self->name()
      .": not a more-specific prefix\n";
  ($self->is_stub() and not $prefix->isa('IPAM::Address'))
    and die "Can't add a prefix ".$prefix->name()." to a stub network "
      .$self->name()."\n";
  if (defined $self->{plen} and $self->{plen} != $prefix->ip()->masklen()) {
    my ($file, $line) = $self->nodeinfo();
    die "Prefix length of ".$prefix->name()
      ." does not match required prefix length ".$self->{plen}
	." of containing prefix ".$self->name()
	  ." (defined at $file, line $line)\n";
  }
  $self->{prefix_r}->add($prefix);
}

=item C<registry()>

  my $registry = $prefix->registry();

Returns the L<IPAM::Prefix::Registry> of the prefix.

=cut

sub registry($) {
  my ($self) = @_;
  return($self->{prefix_r})
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<NetAddr::IP>, L<IPAM::Address>, L<IPAM::Network>

=cut

package IPAM::Prefix::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Prefix Registry';

=head1 NAME

IPAM::Prefix::Registry - Class of a registry for L<IPAM::Prefix> objects

=head1 SYNOPSIS

  use IPAM::Prefix::Registry;

=head1 DESCRIPTION

The L<IPAM::Prefix::Registry> class is derived from L<IPAM::Registry>.
It stores a list of L<IPAM::Prefix> objects and provides facilities to
search a prefix by its C<name>, C<ip> or C<id> attribute.  All methods
extend the search recursively into the registries of more-specific
prefixes in a depth-first manner.

=head1 EXTENDED INSTANCE METHODS

=over 4

=item C<add($prefix)>

  eval { $prefix_r->add($prefix) } or die $@;

Adds the L<IPAM::Prefix> object C<$prefix> to the registry.  An
exception is raised if C<$prefix> overlaps with any of the already
registered prefixes.  In particular, the method does not descend into
the registries of the L<IPAM::Prefix> objects, i.e. it is not possible
to add a prefix that is a more-specific of a prefix that is already
registered.

=cut

sub add($$$) {
  my ($self, $prefix_new) = @_;
  my $next_prefix = $self->iterator(undef, $prefix_new->af());
  while (my $prefix = $next_prefix->()) {
    (($prefix->contains($prefix_new) or $prefix_new->contains($prefix))
	and $prefix->ip() != $prefix_new->ip()) and
	die $self->{name}.": can't add prefix ".$prefix_new->name()
	.", overlaps with ".$prefix->name()."\n";
  }
  ## Identical prefixes are caught by the super class.
  $self->SUPER::add($prefix_new);
  ## Keep lists of prefixes by address family to improve performance
  ## of the iterator() and prefixes() method.
  $self->{things_by_af}{$prefix_new->af()}{$prefix_new->name()} = $prefix_new;
}

sub _base_method_by_af($$$$) {
  my ($self, $method, $sorter, $af) = @_;
  $self->{tmp} = $self->{things};
  $self->{things} = $self->{things_by_af}{$af};
  my @result = IPAM::Registry->can($method)->($self, $sorter);
  $self->{things} = $self->{tmp};
  return(@result);
}

sub _common($$$$) {
  my ($self, $method, $sorter, $af) = @_;
  $af and return(_base_method_by_af($self, $method, $sorter, $af));
  return(IPAM::Registry->can($method)->($self, $sorter));
}

=item C<iterator($sorter, $af)>

  my $next = $prefix_r->iterator(undef, '6');
  while (my $prefix = $next->()) {
    print $prefix->name()."\n";
  }

Extends the base method to include an optional argument C<$af> that
restricts the iterator to a specfific address family.

=cut

sub iterator($$$) {
  my ($self, $sorter, $af) = @_;
  return((_common($self, 'iterator', $sorter, $af))[0]);
}

=item C<things($sorter, $af)>

  my @prefixes = $prefix_r->things(undef, '4');

Extends the base method to include an optional argument C<$af> that
restricts the list to a specfific address family.

=cut

sub things($$$) {
  my ($self, $sorter, $af) = @_;
  return(_common($self, 'things', $sorter, $af));
}

=item C<lookup($name)>

Extends the base method to search the registries of stored prefixes
recursively in a depth-first manner.

=back

=cut

sub lookup($$) {
  my ($self, $name) = @_;
  my $result;
  my $next = $self->iterator();
  while (my $prefix = $next->()) {
    $prefix->name() eq $name and return($prefix);
    $result = $prefix->registry()->lookup($name) and return($result);
  }
  return(undef);
}

=head1 INSTANCE METHODS

=over 4

=item C<af_list()>

  my @af_list = $prefix_r->af_list();

Returns a list of address families that are represented in the
registry.

=cut

sub af_list($) {
  my ($self) = @_;
  return(keys(%{$self->{things_by_af}}));
}

=item C<lookup_by_ip($ip)>

  my $prefix = $prefix_r->lookup_by_ip($ip);
  my ($prefix, @path) = $prefix_r->lookup_by_ip($ip);

If called in a scalar context, returns the uniqe L<IPAM::Prefix>
object that matches the L<NetAddr::IP> object C<$ip> or undef if no
match is found.  If called in a list context, it also returns the list
of L<IPAM::Prefix> objects that were traversed during the search.  The
last element of this list is the most specific covering prefix of
C<$ip>.  The following code covers alle possible cases

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
  my ($result, @path);
  my $next = $self->iterator();
  while (my $prefix = $next->()) {
    if ($prefix->ip() == $ip) {
      $result = $prefix;
      last;
    } elsif ($prefix->ip()->version() == $ip->version()
	     and $prefix->ip()->contains($ip)) {
      ## Note: the version check above is needed to work around
      ## a probable bug in NetAddr::IP.  Otherwise, 0.0.0.0/0 is
      ## considered to be contained in ::/0, even though the versions
      ## are obviously different.
      ($result, @path) = $prefix->registry()->lookup_by_ip($ip);
      unshift(@path, $prefix);
      last;
    }
  }
  if (wantarray()) {
    return($result, @path);
  } else {
    return($result);
  }
}

=item C<lookup_by_id($id)>

  my @prefixes = $prefix_r->lookup_by_id($id);

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
  my @result;
  my $next = $self->iterator();
  while (my $prefix = $next->()) {
    push(@result, $prefix) if ($prefix->id() eq $name and
			       (not $stub_only or $prefix->is_stub()));
    ### Don't descend into stub networks.  Those contain addresses
    ### only.
    unless ($prefix->is_stub()) {
      push(@result, $prefix->registry()->lookup_by_id($name, $stub_only));
    }
  }
  return(@result);
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<IPAM::Prefix>, L<NetAddr::IP>

=cut

1;
