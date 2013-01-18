#### -*- mode: CPerl; -*-
#### File name:     Domain.pm
#### Description:   IPAM::Domain class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Domain.pm,v 1.14 2013/01/16 15:12:56 gall Exp gall $

package IPAM::Domain;
our @ISA = qw(IPAM::Thing);

=head1 NAME

IPAM::Domain - Class that describes a DNS domain within a zone

=head1 SYNOPSIS

  use IPAM::Domain;

=head1 DESCRIPTION

The L<IPAM::Domain> class is derived from L<IPAM::Thing>.  It stores
all DNS RRsets associated with a domain name.  A L<IPAM::Domain> is
associated with exactly one L<IPAM::Zone> object.  The name of it is a
domain name relative to the name of the zone to which it belongs.

=head1 EXTENDED CLASS METHODS

=over 4

=item C<new($node, $name, $zone)>

  my $domain = IPAM::Domain->new($node, $name, $zone);

Associates the L<IPAM::Zone> object with the domain.

=cut

sub new($$$) {
  my ($class, $node, $name, $zone) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{zone} = $zone;
  return($self);
}

=back

=head1 INSTANCE METHODS

=over 4

=item C<fqdn()>

  my $fqdn = $domain->fqdn();

Returns the fully qualified domain name of the object, which is the
catenation of its own name with the name of its associated
L<IPAM::Zone> object.

=cut

sub fqdn($) {
  my ($self) = @_;
  return(join('.', $self->name(), $self->{zone}->name()));
}

=item C<add_rr($ttl, $type, $rdata, $comment, $dns, @nodeinfo)>

  eval { $domain->add_rr($ttl, $type, $rdata, $comment, $dns) }
    or die $@;

Adds the resource record C>> <$type, $rdata> >> with given C<$ttl> to
the RRsets associated with the domain.  The C<$comment> is included as
actual comment in the output of the RR by the C<print()> method.  The
optional array C<@nodeinfo> is a list of filename and linenumber where
the element of the IPAM database is defined from which the resource
record was derived.

If the record is of type CNAME, exceptions are raised if either a
CNAME or a record of any other type already exists.

If the record is not of type CNAME and the RRset already exists, it is
checked whether C<$ttl> matches the TTL of the RRset.  If this is not
the case, a warning is issued and C<$ttl> is ignored in favor of the
TTL of the existing RRset.

If C<$dns> is a false value, the data is recorded but will not be
output by the C<print()> method (or printed as comment only).  In
addition, none of the checks regarding CNAMEs and TTLs are performed.

=cut

sub add_rr($$$$$$@) {
  my ($self, $ttl, $type, $rdata, $comment, $dns, @nodeinfo) = @_;
  my $key = 'types';
  $type = uc($type);
  if ($dns) {
    (($type eq 'CNAME' && $self->types() != 0
      && not $self->exists_rrset($type)) or
     ($type ne 'CNAME' and grep { $_ eq 'CNAME' } $self->types)) and
       die $self->fqdn()
	 .": mixing of CNAME with other record types not allowed\n";
    if ($self->exists_rrset($type)) {
      if ($type eq 'CNAME') {
	my ($file, $line) = (@{$self->{types}{$type}{rr}})[0]->{nodeinfo};
	die $self->fqdn().": multiple CNAME records not allowed"
	  ." (conflicts with definition at $file, $line)\n";
      }
      my $rrset_ttl = $self->{types}{$type}{ttl};
      unless ($rrset_ttl eq $ttl) {
	my ($file, $line) = @nodeinfo;
	$rrset_ttl > $ttl and $self->{types}{$type}{ttl} = $ttl;
	warn $self->fqdn().": TTL ".
	  (defined $ttl ? $ttl : '<default>')." of new $type RR"
	    ." differs from TTL "
	      .(defined $rrset_ttl ? $rrset_ttl : '<default>')
		." of existing RRset, using smaller value "
		  .$self->{types}{$type}{ttl}." at $file, $line.\n";
      }
    } else {
      ## Create a new RRset
      $self->{types}{$type}{ttl} = $ttl;
    }
  } else {
    $key = 'types_i';
    ## We simply overwrite the TTL of inactive RRsets.  Mismatches
    ## are caught for active RRsets only.
    $self->{$key}{$type}{ttl} = $ttl;
  }
  push(@{$self->{$key}{$type}{rr}}, { rdata => $rdata,
				      comment => $comment,
				      dns => $dns,
				      nodeinfo => [ @nodeinfo ] });
}

=item C<print($FILEH, $indent, $annotate)>

$domain->print(\*STDOUT, 0);

Print all RRsets in valid (but not canonical) master file syntax to
the filehandle referred by C<$FILEH>.  If C<$indent> is an integer,
that number of spaces is prepended to each output line. If
C<$annotate> is true, each RR is accompanied with a comment containing
the file name and line number of the IPAM XML element from which the
data was derived.

=cut

sub print($$$$) {
  my ($self, $FILE, $n, $annotate) = @_;
  my $name = $self->name() ? $self->name() : '@';
  my $indent = (defined $n and $n =~ /^\d+$/) ? ' 'x$n : '';
  foreach my $key (qw/types types_i/) {
    foreach my $type (sort { $a cmp $b } keys(%{$self->{$key}})) {
      my $rrset = \%{$self->{$key}{$type}};
      my $ttl = defined $rrset->{ttl} ? $rrset->{ttl} : '';
      my %rdata;
      foreach my $rr (@{$rrset->{rr}}) {
	## Suppress duplicates.  They are expected for PTR and
	## LOC but less so for other types.
	if (exists $rdata{$rr->{rdata}}) {
	  ($type ne 'PTR' and $type ne 'LOC') and
	    warn "BUG: skipping unexpected duplicate RR: $type ".$rr->{rdata}
	      ." for ".($self->name() ? $self->name() : '@')."\n";
	  next;
	}
	$rdata{$rr->{rdata}} = 1;
	printf $FILE ("$indent%-30s %6s IN %-8s %-s",
		      ($rr->{dns} ? '' : '; <inactive> ').$name,
		      $rrset->{ttl}, $type, $rr->{rdata});
	defined $rr->{comment} and print $FILE " ; ".$rr->{comment};
	if (defined $annotate and $annotate) {
	  my ($file, $line) = @{$rr->{nodeinfo}};
	  defined $file and
	    print $FILE (" ; $file:$line");
	}
	print $FILE "\n";
	## The owner name is only printed for the first RR unless
	## it happens to be commented out ("inactive").
	$rr->{dns} and $name = '';
      }
    }
  }
}

=item C<types()>

  my $types = $domain->types();

Returns a list of RR types associated with the domain.

=cut

sub types($) {
  my ($self) = @_;
  return(keys(%{$self->{types}}));
}

=item C<exists_rrset($type)>

  my $exists = $domain->exists_rrset('A');

Returns true if a RRset of type C<$type> exists, false if not.

=cut

sub exists_rrset($$) {
  my ($self, $type) = @_;
  return(exists $self->{types}{$type});

}

=back

=head1 SEE ALSO

L<IPAM::Thing>, L<IPAM::Zone>

=cut

package IPAM::Domain::Registry;
our @ISA = qw(IPAM::Registry);

1;
