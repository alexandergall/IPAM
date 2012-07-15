#### -*- mode: CPerl; -*-
#### File name:     Zone.pm
#### Description:   IPAM::Zone class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id:$

#### Specialized IPAM::Thing that describes a zone.  
####
#### Extended methods
####   new($node, $name, $directory)
####
#### New methods
####
#### Instance variables
####   directory
####     Scalar, holds the zone's directory name
####   domain_r
####     IPAM::Domain::Registry object
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
comprised of a list of L<IPAM::Domain objects> whose names are relative
to the zone's name.  Each domain object holds all DNS RRsets
associated with the FQDN that results by concatenating the domain's
name with the zone name.

=head1 EXTENDED CLASS METHODS

=over 4

=item new($node, $name, $directory)

my $zone = eval { IPAM::Zone->new($node, $zone, $directory) } or die $@;

Creates a new instance and associates the path name $directory with
the zone.  This path will be used to store the zone file snippets
generated by IPAM.  An exception is raised if the directory doesn't
exist.  This check is skipped if the last element of the path is equal
to 'IGNORE'.

=back

=cut

sub new($$$$) {
  my ($class, $node, $name, $directory) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{directory} = $directory;
  $self->{domain_r} = IPAM::Domain::Registry->new();
  -d $directory or die "Directory $directory for zone $name doesn't exist\n"
    unless basename($directory) eq 'IGNORE';
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item directory()

my $dir = $zone->directory();

Returns the zone's directory.

=cut

sub directory($) {
  my ($self) = @_;
  return($self->{directory});
}

=item add_domain($domain)

eval { $zone->add_domain($domain) } or die $@;

Adds the L<IPAM::Domain> object $domain to the zone.  An exception is
raised if a domain with the same name already exists.

=cut

sub add_domain($$) {
  my ($self, $domain) = @_;
  $self->{domain_r}->add($domain);
}

=item domains()

my @domains = $zone->domains();

Returns the list of L<IPAM::Domain> objects associated with the zone.

=cut

sub domains($) {
  my ($self) = @_;
  return($self->{domain_r}->things());
}

=item lookup_domain($domain)

my $domain = $zone->lookup_domain($domain);

Returns the L<IPAM::Domain> object whose name is $domain or undef if
not found.  Note that the name of a domain is relative to the name of
the zone in which it is contained.

=back

=cut

sub lookup_domain($$) {
    my ($self, $name) = @_;
    return($self->{domain_r}->lookup($name));
}

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

=item lookup_fqdn($fqdn)

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

=item add_rr($node, $fqdn, $ttl, $type, $rdata, $comment, $dns)

eval { $zone_r->add_rr($node, $fqdn, $ttl, $type, $rdata, $comment, $dns);

Finds the zone and domain for $fqdn and adds the specified resource
record by calling the add_rr() instance method of the resulting
L<IPAM::Domain> object.  If the domain does not exist yet, it is
created.

=back

=cut

sub add_rr($$$$$$$$) {
  my ($self, $node, $fqdn, $ttl, $type, $rdata, $comment, $dns) = @_;
  my ($zone, $name) = $self->lookup_fqdn($fqdn);
  defined ($zone) or
    die "Can't associate $fqdn with any configured zone\n";
  my $domain = $zone->lookup_domain($name);
  unless ($domain) {
    $domain = IPAM::Domain->new(undef, $name, $zone);
    $zone->add_domain($domain);
  }
  $domain->add_rr($node, $ttl, $type, $rdata, $comment, $dns);
}

1;