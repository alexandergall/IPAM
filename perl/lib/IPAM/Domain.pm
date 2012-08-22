#### -*- mode: CPerl; -*-
#### File name:     Domain.pm
#### Description:   IPAM::Domain class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Domain.pm,v 1.3 2012/08/17 12:32:37 gall Exp gall $

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

=item new($node, $name, $zone)

my $domain = IPAM::Domain->new($node, $name, $zone);

Associates the L<IPAM::Zone> object with the domain.

=back

=cut

sub new($$$) {
  my ($class, $node, $name, $zone) = @_;
  my $self = $class->SUPER::new($node, $name);
  $self->{zone} = $zone;
  return($self);
}

=head1 INSTANCE METHODS

=over 4

=item fqdn()

my $fqdn = $domain->fqdn();

Returns the fully qualified domain name of the object, which is the
catenation of its own name with the name of its associated
L<IPAM::Zone> object.

=cut

sub fqdn($) {
  my ($self) = @_;
  return(join('.', $self->name(), $self->{zone}->name()));
}

=item add_rr($node, $ttl, $type, $rdata, $comment, $dns)

$domain->add_rr($node, $ttl, $type, $rdata, $comment, $dns);

Adds the resource record <$type, $rdata> with given $ttl to the RRsets
associated with the domain.  $node is a L<XML::LibXML::Node> object
from which the RR is derived.  The $comment is included as actual
comment in the output of the RR by the print() method.  If $dns is
false, the data is recorded but will not be output by the print()
method (or printed as comment only).  A warning is printed if the
RRset of type $type already exists but has a different TTL than $ttl.
In that case, the existing TTL takes precedence.

=cut

sub add_rr($$$$$$$) {
  my ($self, $node, $ttl, $type, $rdata, $comment, $dns) = @_;
  $type = uc($type);
  if ($self->exists_rrset($type)) {
    if ($type eq 'CNAME') {
      my ($file, $line) =
	IPAM::_nodeinfo((@{$self->{types}{$type}{rr}})[0]->{node});
      die $self->fqdn().": multiple CNAME records not allowed"
	." (conflicts with definition at $file, $line)\n";
    }
    my $rrset_ttl = $self->{types}{$type}{ttl};
    $rrset_ttl eq $ttl or
      warn $self->fqdn().": TTL ".($ttl ? $ttl : '<default>')." of new $type RR"
    	." differs from TTL ".($rrset_ttl ? $rrset_ttl : '<default>')
	  ." of existing RRset, ignoring new value.\n";
  } else {
    ## Create a new RRset
    $self->{types}{$type}{ttl} = $ttl;
  }
  (($type eq 'CNAME' and $self->types() == 0) or
   ($type ne 'CNAME' and grep { $_ eq 'CNAME' } $self->types)) and
     die $self->fqdn()
      .": mixing of CNAME with other record types not allowed\n";
  push(@{$self->{types}{$type}{rr}}, { rdata => $rdata,
				       comment => $comment,
				       dns => $dns,
				       node => $node});
}

=item print($FILEH, $indent, $annotate)

$domain->print(\*STDOUT, 0);

Print all RRsets in valid (but not canonical) master file syntax to
the filehandle referred by $FILEH.  If $indent is an integer, that
number of spaces is prepended to each output line. If $annotate is true,
each RR is accompanied with a comment containing the file name and line
number of the IPAM XML element from which the data was derived.

=cut

sub print($$$) {
  my ($self, $FILE, $n, $annotate) = @_;
  my $name = $self->name() ? $self->name() : '@';
  my $indent = (defined $n and $n =~ /^\d+$/) ? ' 'x$n : '';
  foreach my $type (keys(%{$self->{types}})) {
     my $rrset = \%{$self->{types}{$type}};
    my $ttl = defined $rrset->{ttl} ? $rrset->{ttl} : '';
     my %rdata;
    foreach my $rr (@{$rrset->{rr}}) {
      ## Suppress duplicates.  They are expected for PTR and
      ## LOC but less so for other types.
      if (exists $rdata{$rr->{rdata}}) {
	($type ne 'PTR' and $type ne 'LOC') and
	  warn "BUG: skipping unexpected duplicate RR: $type ".$rr->{rdata}
	    ."\n";
	next;
      }
      $rdata{$rr->{rdata}} = 1;
      printf $FILE ("$indent%s%-30s %6s IN %-8s %-s",
		    $rr->{dns} ? '' : ';<inactive>',
    		    $name, $rrset->{ttl}, $type, $rr->{rdata});
      defined $rr->{comment} and print $FILE " ; ".$rr->{comment};
      if (defined $annotate and $annotate) {
	my ($file, $line) = IPAM::_nodeinfo($rr->{node});
	defined $file and
	  print $FILE (" ; $file:$line");
      }
      print $FILE "\n";
      $name = '';
    }

  }
}

=item types()

$types = $domain->types();  

Returns a list of RR types associated with the domain.

=cut
sub types($) {
  my ($self) = @_;
  return(keys(%{$self->{types}}));
}

=item exists_rrset($type)

my $exists = $domain->exists_rrset('A');

Returns true if a RRset of type $type exists, false if not.

=cut

sub exists_rrset($$) {
  my ($self, $type) = @_;
  return(exists $self->{types}{$type});

}

package IPAM::Domain::Registry;
our @ISA = qw(IPAM::Registry);

1;
