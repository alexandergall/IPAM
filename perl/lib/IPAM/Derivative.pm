#### -*- mode: CPerl; -*-
#### File name:     Derivative.pm
#### Description:   IPAM::Derivative class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 1 2026

package IPAM::Derivative;
our @ISA = qw(IPAM::Thing);
use IPAM::Host;

=head1 NAME

IPAM::Derivative - Class for storing mappings of derivatives to hosts

=head1 SYNOPSIS

  use IPAM::Derivative;

=head1 DESCRIPTION

L<IPAM::Derivative> is derived from L<IPAM::Thing>. A derivative is a
domain name that owns resource records defined in the scope of a host
but does not match the name of that host. The relationship between a
host and a derivation is anchored at the level of a resource record
definition. A host can have any number of derivatives and a derivative
can have any number of derivers, i.e. hosts from which it receives
individual resource records. The L<IPAM::Derivative> object keeps
track of the derivers of a particular derivation by storing references
to the corresponding L<IPAM::Host> objects.

The reverse mapping from a host to its derivatives is stored in a
L<IPAM::Derivative::Registry> within the L<IPAM::Host> object.

=head1 CLASS METHODS

=over 4

=item C<new($node, $name, @host)>

  my $drv = IPAM::Derivative->new($node, $name, @hosts);

Creates a derivation for the domain name C<$name> and adds the list of
L<IPAM::Host> objects C<@host> to its list of derivers. If C<@hosts>
is omitted, no derivers are added to the derivative.

=back

=cut

sub new($$$@) {
  my ($class, $node, $name, @hosts) = @_;
  my $self = $class->SUPER::new($node, $name);
  foreach my $host (@hosts) {
    $self->add_host($host);
  }
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<add_host($host)>

  $drv->add_host($host);

Add the L<IPAM::Host> object C<$host> to the derivative. It is safe to
add the same host object multiple times.

=cut

sub add_host($$) {
  my ($self, $host) = @_;
  $self->{hosts}{$host->name()} = $host;
}

=item C<hosts()>

  my @hosts = $derivative->hosts();

Return a list of all L<IPAM::Host> objects from which the derivative
was derived. The list is sorted by the name of the hosts.

=cut

sub hosts($) {
  my ($self) = @_;
  return sort { $a->name() cmp $b->name() } values(%{$self->{hosts}});
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Host>

=cut

package IPAM::Derivative::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Derivative registry';

1;
