#### -*- mode: CPerl; -*-
#### File name:     RR.pm
#### Description:   IPAM::RR class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jan 23 2017

package IPAM::RR;
use IPAM;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::RR - Class that describes a generic Routing Registry object

=head1 SYNOPSIS

  use IPAM::RR;

=head1 DESCRIPTION

The L<IPAM::Inetnum> class is derived from L<IPAM::Thing>.  It
describes a generic "Routing Registry" object, which is essentially a
collection of arbitrary attributes and their associated value, like,
for example, in the RIPE WHOIS database.  A RR object is associated
with a "source" and a "type".  The source serves as a name space for
types.  The L<IPAM::RR> class is agnostic about the semantics of
sources and types. The IPAM data model currently defines the following
sources and types

=over 4

=item Source C<RIPE>

Objects in this name space use the structure and semantics of the
corresponding objects in the RIPE database.

=over 4

=item Type C<route>

=item Type C<route6>

=item Type C<inetnum>

=item Type C<inet6num>

=back

=item Source C<SWITCH>

This defines a local name space used at SWITCH

=over 4

=item Type C<inetnum>

=item Type C<inet6num>

=back

=back

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $name, $source, $type, @attributes)>

  my $rr = eval { IPAM::RR->new($node, '192.168.0.0/16+AS65534',
                                'RIPE', 'route', ( { descr => 'Foo' },
                                                   { origin => 'AS65534 } ))
             or die $@;

A L<NetAddr::RR> object is created from a name, source, type and a
list of attributes.  The name of the underlying L<IPAM::Thing> that
gets created is constructed from C<$name> prepended with C<$source>
and C<$type>, spearated by a '+'.  In this example, the effective name
would be C<RIPE+route+192.168.0.0/16+AS65534> and it must be unique
for all objects stored in the same L<IPAM::RR::Registry> registry.
The IPAM is aware of the semantics of object types and choses a name
with the appropriate uniqueness properties (e.g. by appending the
C<origin> attribute for an object of type C<route> or C<route6>).

Attributes are passed as a list of hashes with a single key/value
pair.  An exception is raised if a hash with multiple key/value pairs
is encountered.  The order of the attributes is strictly maintained in
all operations of the L<IPAM::RR> module.

=back

=cut

sub new($$$$$) {
  my ($class, $node, $name, $source, $type, @attributes) = @_;
  my $self = $class->SUPER::new($node, "$source+$type+$name");
  $self->{source} = $source;
  $self->{type} = $type;
  map { keys(%{$_}) == 1 or die "Malformed attribute" } @attributes;
  push(@{$self->{attributes}}, @attributes);
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<source()>

  my $source = $rr->source();

Returns the source of the L<IPAM::RR> object.

=cut

sub source($) {
  my ($self) = @_;
  return($self->{source});
}

=item C<type()>

  my $type = $rr->type();

Returns the type of the L<IPAM::RR> object.

=cut

sub type($) {
  my ($self) = @_;
  return($self->{type});
}

=item C<attributes()>

  my @atributes = $rr->attributes();

Returns the attributes of the L<IPAM::RR> object exactly as passed to
the C<new()> method.

=cut

sub attributes($$) {
  my ($self) = @_;
  return(@{$self->{attributes}});
}

=item C<dump()>

  print $rr->dump();

Returns the attributes in a human-readable form as an array of
strings, each of the form C<attribute: value>.

=cut

sub dump($) {
  my ($self) = @_;
  my @result;
  sub format_attr(@) {
    my ($name, $value) = @_;
    return sprintf("%-11s %s\n", $name.":", $value);
  }
  map { push(@result, format_attr(%{$_})) } @{$self->{attributes}};
  return(@result);
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<NetAddr::IP>, L<IPAM::Address>, L<IPAM::Network>

=cut

package IPAM::RR::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'RR Registry';

=head1 NAME

IPAM::RR::Registry - Class of a registry for L<IPAM::RR> objects

=head1 SYNOPSIS

  use IPAM::RR::Registry;

=head1 DESCRIPTION

The L<IPAM::RR::Registry> class is derived from L<IPAM::Registry>.
It stores a list of L<IPAM::RR> objects.

=head1 INSTANCE METHODS

=over 4

=item C<lookup_by_attributes($source, $type, $predicates)>

  my @rrs = $rr_r->lookup_by_attributes('RIPE', 'route', { origin => sub { shift =~ /AS[0-9]+/ } });

Returns a list of L<IPAM::RR> objects of type C<$type> in source
C<$source> whose attributes satisfy the predicates supplied in
C<$predicates>, which must be a reference to hash, whose keys
correspond to the attribute to check and whose keys are anonymous
subroutines that return true if the attribute's value satisfies the
predicate and false if not. The subroutine is called with the value of
the attribute as its only argument. For attributes that occur multiple
times, all instances must satisfy the predicate for a successfull
match.

For example, to perform a simple pattern match against the regular
expression C<regex>, the following predicate function can be used

  sub { shift =~ /<pattern>/ }

=cut


sub lookup_by_attributes($$$$) {
  my ($self, $source, $type, $predicates) = @_;
  my @result;
  my $next = $self->iterator();
 RR:
  while (my $rr = $next->()) {
    next unless ($rr->source() eq $source and $rr->type() eq $type);
    my %attributes;
    map { my ($name, $value) = %{$_};
          push(@{$attributes{$name}}, $value) } $rr->attributes();
    ## Reset the each() iterator
    scalar(keys(%{$predicates}));
    while (my ($name, $p) = each %{$predicates}) {
      next RR unless exists $attributes{$name};
      map { next RR unless $p->($_) } @{$attributes{$name}};
    }
    push(@result, $rr);
  }
  return(@result);
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<IPAM::RR>

=cut

1;

## Local Variables:
## mode: CPerl
## End:
