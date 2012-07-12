#### -*- mode: CPerl; -*-
#### File name:     Registry.pm
#### Description:   IPAM::Registry class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id:$
package IPAM::Registry;
our $name = 'Generic registry';

=head1 NAME

IPAM::Registry - Base class for a registry of IPAM::Thing objects

=head1 SYNOPSIS

use IPAM::Registry;

=head1 DESCRIPTION

This is essentially a hash keyed by the names of the L<IPAM::Thing>
objects that are stored in it with a built-in check for uniqueness of
the names.  For the purpose of this check, all names are converted to
lower case using the Perl built-in lc().

The registry is associated with a name which is printed in error
messages to make them more meaningful.  The default name is "Generic
registry" and should be overriden by derived classes.

=head1 METHODS

=over 4

=item new()

my $registry = IPAM::Registry->new();

Creates a new IPAM::Registry object.

=cut

sub new($) {
  my ($class) = @_;
  my $self = { counter => 0 };
  { no strict 'refs';
    if (defined ${"${class}::name"}) {
      $self->{name} = ${"${class}::name"};
    } else {
      $self->{name} = $name;
    }
  }
  return(bless($self, $class));
}

=item name()

my $name = $registry->name();

Returns the name of the registry.

=cut

sub name($) {
  my ($self) = @_;
  return($self->{name});
}

=item add($thing)

eval { $registry->add($thing) } or die $@;

Adds the IPAM::Thing object $thing to the registry.  An exception is
raised if the lower-case version of the name of $thing (obtained by
the call lc($thing->name())) is already present in the registry.

=cut

sub add($$) {
  my ($self, $thing) = @_;
  my $name = $thing->name();
  my $name_lc = lc($name);
  if (exists $self->{lc_map}{$name_lc}) {
    my $prev_thing = $self->{things}{$self->{lc_map}{$name_lc}};
    my $prev_def = '';
    if (my ($file, $line) = $prev_thing->nodeinfo()) {
      $prev_def = " (previous definition at $file, line $line)";
    }
    die "$self->{name}: duplicate definition of $name$prev_def\n";
  }
  $self->{counter}++;
  $self->{things}{$name} = $thing;
  $self->{lc_map}{$name_lc} = $name;
}

=item lookup($name)

my $thing = $registry->lookup('foo');

Returns a reference to the unique IPAM::Thing object stored in the
registry whose name converted to lower-case matches the lower-case
version of $name.  If no such Thing exists, the method returns undef
or an empty list when called in scalar or list context, respectively.

=cut

sub lookup($$) {
  my ($self, $name) = @_;
  exists $self->{lc_map}{lc($name)} and
      return($self->{things}{$self->{lc_map}{lc($name)}});
  return();
}

=item iterator($sorter)

my $next = $registry->iterator();
while (my $thing = $next->()) {
  print $thing->name()."\n";
}

Generates an iterator for all Things in the registry.  This is a
closure that returns the next Thing each time it is called and returns
undef after all Things have been processed.  An anonymous subroutine
can be passed to sort the Things in a particular order.  The
subroutine is called within a sort() statement like this:

  sort { $sorter($a, $b) }

where $a and $b are references to IPAM::Thing objects.  By default, no
sorting is done.  To sort by name, for example, one would use

  my @things = $thing->iterator(sub { my ($a, $b) = @_; 
                                      $a->name() cmp $b->name() });

=cut

### Note: the current implementation of iterator() is simply a wrapper
### around a call to things(), i.e. it has exactly the same overhead.
### There really is not much point to having both methods, except
### maybe to have a choice in coding style.  This is unavoidable (I
### think) if sorting is used.  Without sorting, iterator() could be
### implemented to not require building the entire list of things in
### advance, which could be more efficient.
sub iterator($$) {
  my ($self, $sorter) = @_;
  my @things = $self->things($sorter);
  return (sub {
	    my $thing = pop(@things) or return(undef);
	    return($thing);
	  });
}

=item thing($sorter)

my @things = $registry->things();

Returns a list of all Things stored in the registry.  Usage of the
$sorter argument is the same as that for the iterator() method.

=cut

sub things($$) {
  my ($self, $sorter) = @_;
  if (defined $sorter) {
    return(sort { &$sorter($a, $b) } values(%{$self->{things}}));
  } else {
    return(values(%{$self->{things}}));
  }
}

=item counter()

my $things = $registry->counter();

Returns the number of Things in the registry.

=cut

sub counter($) {
  my ($self) = @_;
  return($self->{counter});
}

1;
