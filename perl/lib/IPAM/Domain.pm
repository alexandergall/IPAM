#### -*- mode: CPerl; -*-
#### File name:     Domain.pm
#### Description:   IPAM::Domain class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Domain.pm,v 1.18 2013/09/09 08:25:56 gall Exp gall $

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
  $self->name() or return($self->{zone}->name());
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

An exception is raised if

=over 4

=item *
C<$type> is 'CNAME' but other records (including CNAME) already exist.

=item *
C<$type> is not 'CNAME' but a CNAME record already exists

=item *
C<$type> is a 'CNAME' and the Domain Object is at the apex of the zone.

=back

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
    if ($type eq 'CNAME' && $self->types() != 0
	&& not $self->exists_rrset($type)) {
      ## We're trying to add a CNAME but at least one non-CNAME
      ## RR already exists.  Try to make the error message more
      ## meaningful by including information about one of
      ## these existing records.
      my ($file, $line);
    TYPE:
      for $type ($self->types()) {
	for my $rr (@{$self->{types}{$type}{rr}}) {
	  ($file, $line) = @{$rr->{nodeinfo}};
	  last TYPE if defined $file;
	}
      }
      die $self->fqdn()
	.": can't add a CNAME record when records of other types already exist"
	  .(defined $file ? " (conflicts with definition at "
	   ."$file, $line)" : '')."\n";
    }
    if ($type ne 'CNAME' and grep { $_ eq 'CNAME' } $self->types) {
      ## We're trying to add a non-CNAME RR but a CNAME already exists
      my ($file, $line) = @{(@{$self->{types}{'CNAME'}{rr}})[0]->{nodeinfo}};
      die $self->fqdn()
	.": can't add record of type $type when a CNAME already exists"
	  .(defined $file ? " (conflicts with definition at "
	    ."$file, $line)" : '')."\n";
    }
    ($type eq 'CNAME' and not $self->name()) and
      die $self->fqdn().": CNAME not allowed at zone apex\n";
    if ($self->exists_rrset($type)) {
      if ($type eq 'CNAME') {
	my ($file, $line) = @{(@{$self->{types}{$type}{rr}})[0]->{nodeinfo}};
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

=item C<print($FILEH, $indent, $annotate, $repeat_owner)>

$domain->print(\*STDOUT);

Print all RRsets in valid (but not canonical) master file syntax to
the filehandle referred by C<$FILEH>.  If C<$indent> is an integer,
that number of spaces is prepended to each output line. If
C<$annotate> is true, each RR is accompanied with a comment containing
the file name and line number of the IPAM XML element from which the
data was derived.  If C<$repeat_owner> is a true value, the owner name
of a RR is repeated on every line.

=cut

sub print($$$$) {
  my ($self, $FILE, $n, $annotate, $repeat_owner) = @_;
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
	## If $repeat_owner is true, print the owner name for every
	## record.  Otherwise, it is printed only for the first record
	## unless the record is inactive.  Without this last
	## condition, the owner name would be missing completely if
	## the very first RR happens to be inactive.
	$name = '' if ($rr->{dns} and not $repeat_owner);
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
