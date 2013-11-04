#### -*- mode: CPerl; -*-
#### File name:     Alternative.pm
#### Description:   IPAM::Alternative class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Sep 10 2012

package IPAM::Alternative;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Alternative - Base class for alternative DNS configurations

=head1 SYNOPSIS

  use IPAM::Alternative;

=head1 DESCRIPTION

L<IPAM::Alternative> is derived from L<IPAM::Thing>.  An alternative
is a method to generate different DNS records for particular objects
depending on the value of a configuration variable.  Such a variable
is called a C<label> and it is defined in a C<< <alternative> >> XML
element in the IPAM database.

The C<label> is an arbitrary string that must uniquely identify a
particular alternative in the IPAM database.  Note that the C<label>
is not a FQDN.

At any time, a C<label> is assigned to a particular C<state> out of a
set of allowed states, which are defined by sub-elements C<<
<allowed-state> >> of a C<< <alternative> >> element.  This assignment
selects one of the alternatives represented by the set of allowed
states as being active.

Alternatives are referenced from elements within a C<< <host> >>
definition through C<alternative> attributes in various sub-elements.
Such an attribute is of the form C<label:state> and selects a
particular state of an alternative for which DNS information should be
generated from the object that uses the attribute.

An alternative can be viewed as a mechanism to annotate a mapping of a
partiular L<IPAM::Host> object to some other object.  Currently, there
exist three types of mappings, which are labeled by constants exported
by the L<IPAM::Alternative> class

=over 4

=item IPAM::Alternative::MAP_ADDRESS

Maps a host to a L<IPAM::Address> object.

=item IPAM::Alternative::MAP_ALIAS

Maps a host to a L<IPAM::Thing>, which holds the name of a DNS alias
(CNAME) assigned to the host.

=item IPAM::Alternative::MAP_RR

Maps a host to a DNS resource record represented by a hash with the
following keys derived from the C<< <rr> >> element that defines the
RR in the IPAM database

=over 4

=item type

RR type

=item ttl

TTL of the RR

=item rdata

Contents of the RR

=item nodeinfo

A list containing the file name and line number where the C<< <rr> >>
element is defined in the IPAM database.

=back

The L<IPAM::Alternative> class is used to keep track of alternatives
and their usage.  For each label defined by a C<< <alternative> >>
element in the IPAM database, an instance of this class is generated.
It holds the current state of the alternative as well as the set of
allowed states.  For each allowed state, the object also stores an
array of mappings that use it.  Such a mapping consists of a tuple
(i.e. ordered set) of two object references.  The first reference
points to a L<IPAM::Host> object and the the second one to an object
that depends on the mapping type as described above.

L<IPAM::Alternative> provides methods to register and query the
alternatives contained in the IPAM.

=head1 CLASS METHODS

=over 4

=item C<new($node, $label, @allowed_states)>

  my $thing = IPAM::Alternative->new($node, 'foo', ('bar', 'baz'));

Creates an alternative with label C<$label> and the set of allowed
states stored in the array of strings C<@allowed-states>.

=back

=cut

use constant { MAP_ADDRESS => 'address',
	       MAP_ALIAS => 'alias',
	       MAP_RR => 'rr',
	     };

sub new($$$) {
  my ($class, $node, $label, @states) = @_;
  my $self = $class->SUPER::new($node, $label);
  map { $_ = lc($_) } @states;
  @{$self->{states}}{@states} = ();
  $self->{state} = undef;
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<state()>

  my $name = $alt->state();

Returns the current state of the alternative C<$alt>.

=item C<state($state)>

  eval { $alt->state('foo') } or die $@;

Sets the state of the alternative C<$alt> to that given by C<$state>.
An exception is raised if C<$state> is not one of the allowed states
with which C<$alt> was created.  Returns the previous state of the
alternative.

=cut

sub state($$) {
  my ($self, $state) = @_;
  my $old_state = $self->{state};
  if (defined $state) {
    $state = lc($state);
    exists $self->{states}{$state} or
      die "Can't set alternative ".$self->name()." to $state: "
	." not in list of allowed states ("
	  .join(', ', $self->allowed_states()).")\n";
    $self->{state} = $state;
  }
  return($old_state);
}

=item C<allowd_states()>

  my @states = $alt->allowed_states();

Return the list of allowed states that was passed to C<new()> when the
object was created.

=cut

sub allowed_states($) {
  my ($self) = @_;
  return(keys(%{$self->{states}}));
}

=item C<check_state($state)>

  my $status = $alt->check_state('foo');
  if (defined $status) {
    print "State foo not allowed for ".$alt->name()."\n";
  } else {
    print "State foo is ".($status ? 'active' : 'inactive')."\n";
  }

Checks whether the alternative currently is in state C<$state> or not
and returns a true or false value, respectively.  If C<$state> is not
among the allowed states of the alternative, undef is returned.

=cut

sub check_state($$) {
  my ($self, $state) = @_;
  $state = lc($state);
  exists $self->{states}{$state} or return(undef);
  return($self->{state} eq $state);
}

=item C<add_mapping($type, $host, $object)>

  $alt->add_mapping(IPAM::Alternative::MAP_ADDRESS, $host, $address);

Registeres a mapping of type C<$type> from the L<IPAM::Host> object to
the type-specific object $object.

=cut

sub add_mapping($$$$) {
  my ($self, $state, $type, $host, $thing) = @_;
  $self->find_mapping($type, $host, $thing) and
    die "BUG: duplicate alternative mapping of type $type "
      ."($host, $thing)";
  push(@{$self->{states}{$state}{$type}}, [$host, $thing]);
}

=item C<find_mapping($type, $host, $object)>

  my $state = $alt->find_mapping(IPAM::Alternative::MAP_ADDRESS,
                    $host, $address)

Searches the alternative for a mapping of type C<$type> between the
L<IPAM::Host> object and the type-specific object C<$object> and
returns the state for which the mapping has been registered or undef
if no match is found.

=cut

sub find_mapping($$$) {
  my ($self, $type, $host, $thing) = @_;
  foreach my $state (keys(%{$self->{states}})) {
    foreach my $mapping (@{$self->{states}{$state}{$type}}) {
      return($state)
	if (@$mapping[0] eq $host and @$mapping[1] eq $thing);
    }
  }
  return(undef);
}

=item C<find_host($host)>

  if (my $ref = $alt->find_host($host)) {
    foreach my $state (keys(%{$ref})) {
      map { print $host->name()." state $state type $_\n" }
        @{$ref->{$state}};
    }
  } else {
    print "No mapping for ".$host->name()." in ".$alt->name()."\n";
  }

Searches the alternative C<$alt> for mappings for the L<IPAM::Host>
object $host and returns a reference to a hash keyed by the name of
the states for which such mappings exist.  The values are themselves
hashes keyed by the type of mapping that contain a list of the
corresponding objects.

The undef value is returned if no mappings exist.

=cut

sub find_host($$) {
  my ($self, $host) = @_;
  my $result = {};
  foreach my $state (keys(%{$self->{states}})) {
    foreach my $type (keys(%{$self->{states}{$state}})) {
      map { @$_[0] eq $host and push(@{$result->{$state}{$type}}, @$_[1]) }
	@{$self->{states}{$state}{$type}};
    }
  }
  keys(%{$result}) and return($result);
  return(undef);
}

=item C<find_alias($fqdn)>

  if (my $ref = $alt->find_alias($fqdn)) {
    foreach my $state (keys(%{$ref})) {
      map { print "Canonical name for $fqdn in state $state: "
             .@$_[0]->name()."\n";
        @{$ref->{$state}};
    }
  } else {
    print "No alias mapping for $fqdn in ".$alt->name()."\n";
  }

Searches the alternative C<$alt> for mappings of type MAP_ALIAS that
match the FQDN $fqdn and returns a reference to a hash keyed by the
name of the states for which such mappings exist.  Each value is a
list that contains both elements of the mapping, i.e. a L<IPAM::Host>
objects that defines the canonical name of the alias and a
L<IPAM::Thing> object that describes the alias itself.  While multiple
such mappings can exist, at most one of them can be active at any time
due to the singleton nature of DNS CNAME records.

The undef value is returned if no mappings exist.

=cut

sub find_alias($$) {
  my ($self, $fqdn) = @_;
  my $result = {};
  foreach my $state (keys(%{$self->{states}})) {
    next unless exists $self->{states}{$state}{IPAM::Alternative::MAP_ALIAS};
    map { lc(@$_[1]->name()) eq lc($fqdn) and
	    push(@{$result->{$state}}, [@$_]) }
      @{$self->{states}{$state}{IPAM::Alternative::MAP_ALIAS}};
  }
  keys(%{$result}) and return($result);
  return(undef);
}

=item C<mappings($state)>

  my $ref = $alt->mappings('foo');
  if (defined $ref) {
    foreach my $type (keys(%$ref)) {
      print "Type $type\n";
      foreach my $mapref (@{$ref->{$type}}) {
        print "Host ".@$mapref[0]->name."\n";
        print "Object @$mapref[1]\n";
      }
    }
  }

Returns all mappings for the state C<$state> in the form of a
reference to a hash, which is keyed by the type identifiers.  The
values are arrays of 2-element arrays whose first element is the
reference to the L<IPAM::Host> object and second element is the
reference to the other object of the mapping.

=cut

sub mappings($$) {
  my ($self, $state) = @_;
  $state = lc($state);
  exists $self->{states}{$state} or return(undef);
  return(\%{$self->{states}{$state}});
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Host>

=cut

package IPAM::Alternative::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Alternative registry';

=head1 NAME

IPAM::Alternative::Registry - Class of a registry for L<IPAM::Alternative> objects

=head1 SYNOPSIS

  use IPAM::Alternative;

=head1 DESCRIPTION

The L<IPAM::Alternative::Registry> class is derived from L<IPAM::Registry>.
It stores a list of L<IPAM::Alternative> objects.

=head1 INSTANCE METHODS

=over 4

=item C<find_mapping($type, $host, $object)>

  my ($alt, $state) = $ipam->registry(IPAM::REG_ALTERNATIVE)
             ->find_mapping(IPAM::Alternative::MAP_ADDRESS,
                            $host, $address);

Calls the C<find_mapping()> method of each registered alternative and
returns the L<IPAM::Alternative> object and the state therein to
which the mapping belongs or an empty list if no match is found.

=cut

sub find_mapping($$$$) {
  my ($self, $type, $host, $thing) = @_;
  foreach my $alt ($self->things()) {
    if (my $state = $alt->find_mapping($type, $host, $thing)) {
        return($alt, $state);
    }
  }
  return();
}

=item C<find_host($host)>

  foreach ($alt_r->find_host($host)) {
    my ($alt, $ref) = @$_;
    print "Alternative ".$alt->name().":\n";
    map { print "\tState $_\n" } keys(%$ref);
  }

Calls the C<find_host()> instance method of each registered
alternative and returns an array of lists containing a reference to
the L<IPAM::Alternative> object and the result of the C<find_host()>
method call for each alternative that contains a mapping for the
L<IPAM::Host> object C<$host>.

=cut

sub find_host($$) {
  my ($self, $host) = @_;
  my @result;
  foreach my $alt ($self->things()) {
    next unless my $ref = $alt->find_host($host);
    push(@result, [$alt, $ref]);
  }
  return(@result);
}

=item C<find_alias($fqdn)>

  foreach ($alt_r->find_alias($fqdn)) {
    my ($alt, $ref) = @$_;
    print "Alternative ".$alt->name().":\n";
    map { print "\tState $_\n" } keys(%$ref);
  }

Calls the C<find_alias()> instance method of each registered
alternative and returns an array of lists containing a reference to
the L<IPAM::Alternative> object and the result of the C<find_alias()>
method call for each alternative that contains a mapping for the
FQDN $host.

=cut

sub find_alias($$) {
  my ($self, $fqdn) = @_;
  my @result;
  foreach my $alt ($self->things()) {
    next unless my $ref = $alt->find_alias($fqdn);
    push(@result, [$alt, $ref]);
  }
  return(@result);
}
1;
