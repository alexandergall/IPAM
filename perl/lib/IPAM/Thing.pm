#### -*- mode: CPerl; -*-
#### File name:     Thing.pm
#### Description:   IPAM::Thing class
#### Author:        Alexander Gall <gall@switch.ch>
#### Created:       Jun 5 2012
#### RCS $Id: Thing.pm,v 1.9 2013/01/09 16:03:25 gall Exp gall $
package IPAM::Thing;

=head1 NAME

IPAM::Thing - Base class for named Things

=head1 SYNOPSIS

  use IPAM::Thing;

=head1 DESCRIPTION

L<IPAM::Thing> is the base class for all objects stored in the IPAM.
A basic Thing has the following properties.

=over 4

=item Name

This is an arbitrary string that identifies the Thing.  If the Thing
is part of a L<IPAM::Registry>, the name converted to lower-case will
be unique within the registry.

=item Nodeinfo

Most Things in the IPAM are derived from an XML element in the IPAM
database.  In this case, the nodeinfo attribute of a Thing stores the
file name and line number where the XML element from which the Thing
was constructed is defined.

=item Description

The description is a free-form text field that may contain a
human-readable description of the Thing.  When a Thing is created, the
description is initialized to an empty string.

=item TTL

Some Things are used to generate various DNS resource records.  The
TTL of these records is derived from the Thing's TTL attribute. The
TTL is inherited from higher to lower levels of hierarchy within the
IPAM database.

=item Tags

A tag is an arbitrary label that is assigned to the Thing.  The
semantics of a tag is unknown to the IPAM.  It can be used to identify
Things that have some property that cannot be expressed within the
data model of the IPAM.  Tags can be applied as filters to the results
of queries to the IPAM database.

A Thing can have any number of tags.  Tags are either set explicitely
for a Thing or inherited through the hierarchy in the IPAM data model.

=back

=head1 CLASS METHODS

=over 4

=item C<new($node, $name)>

  my $thing = IPAM::Thing->new($node, $name);

Creates a new thing called $name and derives the nodeinfo attribute
from the L<XML::LibXML::Node> object C<$node>, which may be undefined
if the thing is not associated with any XML node in the IPAM database.

=back

=cut

sub new($$$) {
  my ($class, $node, $name) = @_;
  my $self = { nodeinfo => [ IPAM::_nodeinfo($node) ], name => $name,
	       description => '', ttl => undef, tags => {} };
  return(bless($self, $class));
}

=head1 INSTANCE METHODS

=over 4

=item C<name()>

  my $name = $thing->name();

Returns the Thing's name.

=cut

sub name($) {
  my ($self) = @_;
  return($self->{name});
}

=item C<nodeifno()>

  my ($file, $line) = $thing->nodeinfo();

Returns the file name and line number where the XML node associated
with the Thing is defined or an empty list if no node is associated
with the Thing.

=cut

sub nodeinfo($) {
  my ($self) = @_;
  return(@{$self->{nodeinfo}});
}

=item C<description()>

  my $description = $thing->description();

Returns a string that contains free-form text describing the Thing.

=item C<description($descr)>

  $thing->description('Foo bar baz');

Registers the free-from text $descr as a description of the Thing.

=cut

sub description($$) {
  my ($self, $description) = @_;
  if (defined $description) {
    $self->{description} = $description;
  }
  return($self->{description});
}

=item C<ttl()>

  my $ttl = $thing->ttl();

Returns the current TTL of the Thing.

=item C<ttl($ttl)>

  $thing->ttl(3600);

Sets the Thing's TTL to C<$ttl> seconds. Returns the previous value.

=cut

sub ttl($$) {
  my ($self, $ttl) = @_;
  @_ > 1 and return($self->{ttl} = $ttl);
  return($self->{ttl});
}

=item C<has_tags(@tags)>

  $thing->has_tag(qw/foo bar/) and
    print $thing->name()." is tagged as foo and bar\n";

Returns a true value if C<$thing> is tagged with all labels in
C<@tags>, false otherwise.  An empty list matches all tags.

=cut

sub has_tags($@) {
  my ($self, @tags) = @_;
  foreach my $tag (@tags) {
    exists $self->{tags}{$tag} or return(undef);
  }
  1;
}

=item C<tags()>

  my $tags = $thing->tags();
  foreach my $tag (keys(%$tags)) {
    print "$tag\n";
  }

Returns a reference to a hash whose keys are the tags assigned to
C<$thing>.  The associated value of a tag is a reference to an array
of L<IPAM::Thing> objects which the tag was inherited from.  An empty
array indicates that the tag was set explicitely for the Thing.

=cut

sub tags($) {
  my ($self) = @_;
  return(\%{$self->{tags}});
}

=item C<tags_iterator()>

  my $next_tag = $thing->tags_iterator();
  while (my ($tag, $things_ref) = next_tag->()) {
    print "Tag $tag ".(@$things_ref ?
      "inherited from ".join(', ', map { $_->name() } @$things_ref) : '')."\n";
  }

Returns a closure which iterates through the list of tags assigned to
the Thing.  Upon each invocation, it returns the next tag and the
associated refrence to an array of L<IPAM::Thing> objects as in the
L<IPAM::Thing::tags> instance method.  An empty list is returned after
the last tag has been processed.

=cut

sub tags_iterator($) {
  my ($self) = @_;
  my @tags = keys(%{$self->{tags}});
  return( sub {
	    my $tag = pop(@tags) or return();
	    return($tag, $self->{tags}{$tag});
	  });
}

=item C<set_tags($tags, @things)>

  eval { $thing->set_tags($tags, $inherit) } or die $@;

This method initializes the set of tags for the Thing.  First, all
tags associated with the L<IPAM::Thing> objects in C<@things> are
copied to the Thing.  This is the manner in which tags are inherited.
Note that the same tag can be inherited from multiple Things.

Apart from inheritance, a Thing can also be configured with its own
set of tags (which, in turn, may be inherited by other Things).  This
set is passed in the C<$tags> argument of the method as a string of
tag names separated by colons.  If the first character of a tag is a
hyphen ('-'), the remainder of the tag is interpreted as the name of a
tag which is to be deleted from the set of inherited tags.

An exception is rised if

=over 4

=item 

One of the explicit tags in C<$tags> does not match the regexp \w+

=item

A tag with a leading hyphen does not reference an inherited tag

=item

An explicite tag is identical to an inherited tag

=back

=cut

sub set_tags($$@) {
  my ($self, $tags, @things) = @_;
  foreach my $thing (@things) {
    next unless $thing->isa('IPAM::Thing');
    ### Inherit tags from $thing
    my $next = $thing->tags_iterator();
    while (my ($tag, $things_ref) = $next->()) {
      push(@{$self->{tags}{$tag}}, $thing);
    }
  }
  ### Set own tags
  foreach my $tag (split(':', $tags)) {
    $tag =~ /\w+/ or die $self->name().": illegal tag \'$tag\'\n";
    if ($tag =~ /^-/) {
      $tag =~ s/^-//;
      exists $self->{tags}{$tag} or
	die $self->name().": can't delete non-inherited tag $tag\n";
      delete $self->{tags}{$tag};
    } else {
      exists $self->{tags}{$tag} and
	die $self->name().": duplicate definition of tag $tag "
	  ."(inherited from "
	    .join(',', map { $_->name() } @{$self->{tags}{$tag}}).")\n";
      $self->{tags}{$tag} = [];
    }
  }
  1;
}

=back

=head1 SEE ALSO

L<IPAM::Registry>, L<XML::LibXML>

=cut

1;
