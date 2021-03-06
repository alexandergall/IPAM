#### -*- mode: CPerl; -*-
#### File name:     Zone.pm
#### Description:   IPAM::Zone class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012

package IPAM::Zone;
use IPAM::Thing;
use File::Basename;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Zone - Class that describes a DNS zone

=head1 SYNOPSIS

  use IPAM::Zone;

=head1 DESCRIPTION

The L<IPAM::Zone> class is derived from L<IPAM::Thing>.  A zone is
comprised of a list of L<IPAM::Domain> objects whose names are
relative to the zone's name.  Each domain object holds all DNS RRsets
associated with the FQDN that results by concatenating the domain's
name with the zone name.

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $name, $directory)>

  my $zone = eval { IPAM::Zone->new($node, $zone, $directory) } or die $@;

Creates a new instance and associates the path name C<$directory> with
the zone.  This path will be used to store the zone file snippets
generated by IPAM.  IF C<$directory> is a false value, no directory is
associated with the zone.

=cut

sub new($$$$) {
  my ($class, $node, $name, $directory) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{directory} = $directory;
  $self->{domain_r} = IPAM::Domain::Registry->new();
  return($self);
}

=back

=head1 INSTANCE METHODS

=over 4

=item C<directory()>

  my $dir = $zone->directory();

Returns the zone's directory.

=cut

sub directory($) {
  my ($self) = @_;
  return($self->{directory});
}

=item C<add_domain($domain)>

  eval { $zone->add_domain($domain) } or die $@;

Adds the L<IPAM::Domain> object C<$domain> to the zone.  An exception
is raised if a domain with the same name already exists.

=cut

sub add_domain($$) {
  my ($self, $domain) = @_;
  $self->{domain_r}->add($domain);
}

=item C<domains()>

  my @domains = $zone->domains();

Returns the list of L<IPAM::Domain> objects associated with the zone.

=cut

sub domains($) {
  my ($self) = @_;
  return($self->{domain_r}->things());
}

=item C<lookup_domain($domain)>

  my $domain = $zone->lookup_domain($domain);

Returns the L<IPAM::Domain> object whose name is C<$domain> or undef
if not found.  Note that the name of a domain is relative to the name
of the zone in which it is contained.

=cut

sub lookup_domain($$) {
    my ($self, $name) = @_;
    return($self->{domain_r}->lookup($name));
}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Domain>

=cut

#### Registry for IPAM::Zone objects.
####
#### New methods
package IPAM::Zone::Registry;
use IPAM::Registry;
our @ISA = qw(IPAM::Registry);
our $name = 'Zone registry';

=head1 NAME

IPAM::Zone::Registry - Class of a registry for L<IPAM::Zone> objects

=head1 SYNOPSIS

  use IPAM::Zone;

=head1 DESCRIPTION

The L<IPAM::Zone::Registry> class is derived from L<IPAM::Registry>.
It stores a list of L<IPAM::Zone> objects.

=head1 INSTANCE METHODS

=over 4

=item C<lookup_fqdn($fqdn)>

  my ($zone, $domain) = $zone_r->lookup_fqdn($fqdn);

Searches the registry for the best match (longest common domain name)
of the given FQDN.  Returns the L<IPAM::Zone> object and the relative
name of the FQDN with respect to that zone (called the "domain name"
in the conext of L<IPAM::Domain> objects) or undef if no matching zone
was found.

=cut

sub lookup_fqdn($$) {
  my ($self, $fqdn) = @_;
  my @parts = split(/\./, $fqdn);
  my @name;

  while (@parts) {
    my $domain = join('.', @parts).".";
    my $name = join('.', @name);
    if (my $zone = $self->lookup($domain)) {
      return($zone, $name);
    }
    push(@name, shift(@parts));
  }
  return(undef);
}

=item C<add_rr($fqdn, $ttl, $type, $rdata, $comment, $dns, @nodeinfo)>

  eval { $zone_r->add_rr($fqdn, $ttl, $type, $rdata, $comment, $dns, @nodeinfo);

Finds the zone and domain for C<$fqdn> and adds the specified resource
record by calling the C<add_rr()> instance method of the resulting
L<IPAM::Domain> object.  If the domain does not exist yet, it is
created.

If C<$ttl> is undefined, the zone's default ttl is substituted.

=cut

sub add_rr($$$$$$$@) {
  my ($self, $fqdn, $ttl, $type, $rdata, $comment, $dns, @nodeinfo) = @_;
  my ($zone, $name) = $self->lookup_fqdn($fqdn);
  defined ($zone) or
    die "Can't associate $fqdn with any configured zone\n";
  my $domain = $zone->lookup_domain($name);
  unless ($domain) {
    $domain = IPAM::Domain->new(undef, $name, $zone);
    $zone->add_domain($domain);
  }
  $ttl = $zone->ttl() unless defined $ttl;
  $domain->add_rr($ttl, $type, $rdata, $comment, $dns, @nodeinfo);
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<IPAM::Zone>

=cut

1;
