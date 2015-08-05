#### -*- mode: CPerl; -*-
#### File name:     Alias.pm
#### Description:   IPAM::Alias class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Aug 4 2015

package IPAM::Alias;
our @ISA = qw(IPAM::Thing);
use IPAM::Host;

=head1 NAME

IPAM::Alias - Class for storing mappings of aliases to hosts

=head1 SYNOPSIS

  use IPAM::Alias;

=head1 DESCRIPTION

L<IPAM::Alias> is derived from L<IPAM::Thing>.  An alias is
essentially a pointer to an actual host represented by an
L<IPAM::Host> object.  In the DNS, an alias is represented as the
left-hand side of a CNAME resource record.  As such, an alias can only
point to one particular host.  However, the IPAM's mechanism of
registering alternatives for various objects allows that an alias can
point to any number of different hosts, provided that only a single
alternative is active at any time.

As a corner case, it is also allowed to have an alias point to
multiple L<IPAM::Host> objects that represent the same host name in
different networks, as long as at most one mapping is active in the
DNS.  For this reason, the list of L<IPAM::Host> objects is stored in
an array rather than a L<IPAM::Registry>.

An L<IPAM::Alias> object is not associated with any particular XML
node.  Its sole purpose is to provide easy access to the list of
L<IPAM::Host> objects assoicated with a particular alias name.

Note that the same result can also be obtained with

  $ipam->registry(IPAM::REG_NETWORK)->find_alias($fqdn)

However, that method is much slower.

=head1 CLASS METHODS

=over 4

=item C<new($node, $label, $name)>

  my $alias = IPAM::Alias->new($node, 'foo', 'foo.bar.com');

Creates an alias with label C<$label> and the FQDN C<$name>.

=back

=cut

sub new($$$) {
  my ($class, $node, $label, $name) = @_;
  my $self = $class->SUPER::new($node, $label);
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item C<add_host($host)>

  $alias->add_host($host);

Adds the L<IPAM::Host> object C<$host> to the alias' list of canonical
hosts.  Multiple objects with the same name are allowed.

=cut

sub add_host($$) {
  my ($self, $host) = @_;
  push(@{$self->{hosts}}, $host);
}

=item C<hosts()>

  my @hosts = $alias->hosts();

Returns the list of L<IPAM::Host> objects sorted by name for which
C<$alias> represents an alias.

=cut

sub hosts($) {
  my ($self) = @_;
  return sort { $a->name() cmp $b->name() } @{$self->{hosts}};
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Host>

=cut

package IPAM::Alias::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Alias registry';

1;
