### -*- mode: CPerl; -*-

package IPAM;

=head1 NAME

IPAM - Class for managing an IP Address Space

=head1 SYNOPSIS

use IPAM;

=head1 DESCRITPION

The L<IPAM> module provides an object-oriented interface to a
XML-based database that describes a managed IP address space.  The
managed objects include

=over 4

=item Address Map

The address map contains a hierarchy of address prefixes that cover
the IP address resoucrces to be managed.  It contains two types of
prefixes:

=over 4

=item Network Blocks

A network block designates a range of addresses covered by exactly one
prefix.  Its purpose is to subdivide the managed address space into
functional blocks.  A network block can contain other network blocks
that describe more-specific prefixes.

=item Stub Networks

A stub network (or stub net for brevity) is a special case of a
network block which does not contain any more-specific network blocks.
If the address map is viewed as a tree, only the leave nodes of it can
be marked as stub networks (but a leave node does not have to describe
a stub network).

A stub network contains IP addresses which can be assigned to host
names as detailed below.

=back

Every network block (including stub networks) is associated with
exactly one DNS name.  A name can be associated with any number of
prefixes, but there are essentially only three useful cases for multiple
prefixes per name:

=over 4

=item Fragmented Functional Blocks

If the address range that is designated for a particular purpose,
e.g. for addressing router loopback interfaces, can not be expressed
as a single prefix, the set of prefixes that make up the range can be
labelled with the same name.

=item Dual-Stack Correspondence

In a dual stack environment, there can be ranges of IPv4 and IPv6
addresses that correspond to the same functional entity, e.g. a range
designated to the addressing of router loopback interfaces.  This
correspondence can be reflected by assigning the same name to the
addresses ranges of both address families used for this purpose.

=item IP Subnets

In an IPv6 environment, an IP subnet can have any number of stub nets
(at most one IPv4 and any number of IPv6 but at least one of any
kind).  The mapping between an IP subnet and the stub nets which it
comprises is provided by the name.

=back

=item IPv6 Interface Identifier Registry

This registry contains a mapping of interface identifiers to DNS host names.

=item IP Subnet Definition

The address map defines all stub networks that are contained in the
managed address space.  All stub networks with the same name form one
distinct IP subnet.  The addresses covered by these stub nets can be
assigned to host names in this section of the IPAM database.

An address can be assigned to any number of hosts. At most one of them
can be made the "canonical name" for the address by setting the
attribute "canonical-name" to "true", which is the default.  In other
words, if an address is assigned to multiple hosts, the attribute must
be set to "false" explicitely for all non-canonical hosts.  The effect
of this attribute is twofold.

=over 4

=item 1.

The reverse DNS mapping always points to the canonical name.  The
creation of such a mapping can be suppressed by specifying the
attribute reverse-dns="false" for the <ipv4> or <ipv6> element that
defines the canonical name for the address.

=item 2.

It serves as a simple check for uniqueness of an address.  This is
because the attribute canonical-name="true" is the default and only
one such mapping per address can exist.

=back

In addition, a canonical name can also have any number of aliases
(CNAME DNS records) and any number of arbitrary DNS records.

=item DNS Zone Registry

All DNS names in the database are fully qualified (FQDN - Fully
Qualified Domain Name).  In order to create fragments of DNS master
files that can be included in the main zone master file, the zone cuts
and locations of the master files must be configured into the IPAM
database.  This is done by a simple association of a zone name to a
location within the file system.

=back

=cut

use strict;
use warnings;
use XML::LibXML 1.70;
use NetAddr::IP 4.028 qw(:lower);
use NetAddr::IP::Util qw(add128 ipv6_n2x);
use File::Basename;
use Data::Serializer::Raw;
use IPAM::Thing;
use IPAM::Registry;
use IPAM::Alternative;
use IPAM::IID;
use IPAM::AddressMap;
use IPAM::Prefix;
use IPAM::Address;
use IPAM::Network;
use IPAM::Host;
use IPAM::Zone;
use IPAM::Domain;

our $VERSION = '0.01';

our %af_info = ( 4 => { name => 'ipv4', max_plen => 32, rrtype => 'A', },
		 6 => { name => 'ipv6', max_plen => 128, rrtype => 'AAAA' },
	      );

use constant { REG_ZONE => 'zone',
	       REG_IID => 'iid',
	       REG_NETWORK => 'network',
	       REG_ALTERNATIVE => 'alternative',
	     };

my %default_options = ( verbose => undef,
			base_dir => '.',
			validate => undef,
			warnings => undef);
my $schema_file = 'schemas/ipam.rng';
my %af_tag_to_version = ( v4 => 4, v6 => 6 );
my %registries = ( IPAM::REG_ZONE => { key => 'zone_r',
				       module => 'IPAM::Zone::Registry' },
		   IPAM::REG_IID => {key => 'iid_r',
				     module => 'IPAM::IID::Registry' },
		   IPAM::REG_NETWORK => { key => 'network_r',
					  module => 'IPAM::Network::Registry' },
		   IPAM::REG_ALTERNATIVE => { key => 'alternative_r',
					      module =>
					      'IPAM::Alternative::Registry' },
		 );

my %serializer_opts = ( serializer => 'Storable' );

=head1 CLASS METHODS

=over 4

=item C<new()>

  my $ipam = IPAM->new();

Create an instance of a IPAM object.

=cut

sub new() {
  my ($class, $options) = @_;
  my $self = {};
  $self = \%default_options;
  foreach my $option (keys(%{$options})) {
    exists $default_options{$option} or
      die "Unknown option '$option'";
    $self->{$option} = $options->{$option};
  }
  return(bless($self, $class));
}

=item C<new_from_cache($cache_file)>

  my $ipam = IPAM->new_from_cache($cache_file);

Create an instance of a IPAM object from a cache file that has been
created by the C<cache()> instance method.

=cut

sub new_from_cache($$) {
  my ($class, $file) = @_;
  my $ipam;
  my $serializer = Data::Serializer::Raw->new(%serializer_opts);
  eval { $ipam = $serializer->retrieve($file) }
    or die "Loading database from cache file $file failed: $@";
  return($ipam);
}

=back

=head1 INSTANCE METHODS

=over 4

=item C<load($file)>

  $ipam->load($file) or die;

Load the IPAM database from the given file.

=cut

sub load($$) {
  my ($self, $file) = @_;
  my $parser = XML::LibXML->new() or die "Can't create XML parser: $!";
  $parser->set_options(line_numbers => 1, xinclude => 1,
		       no_xinclude_nodes => 0);
  my $ipam = $parser->load_xml(location => $file);

  ### The RelaxNG validator from XML::LibXML::RelaxNG (which is based on
  ### libxml2) is buggy and can't deal with XInlcude.  Currently, validation
  ### needs to be performed externally.
  if ($self->{validate}) {
    my $schema = XML::LibXML::RelaxNG->new( location =>
					    $self->{base_dir}."/$schema_file" );
    $schema->validate($ipam);
  }

  my $root = $ipam->getDocumentElement();
  $self->{domain} = $root->findvalue('domain');
  $self->{domain} .= '.' unless $self->{domain} =~ /\.$/;

  ## The TTL can be overriden by various lower-level elements that carry
  ## a "ttl" attribute.  Also See the _ttl() helper method.
  ## Note that we need to be careful to distinguish the value 0 from
  ## undef throughout.
  $self->{ttl} = $root->findvalue('ttl');
  $self->{ttl} eq '' and $self->{ttl} = undef;

  ### Create registries
  map { $self->{$registries{$_}{key}} = $registries{$_}{module}->new() }
    keys(%registries);

  $self->_register_alternatives($root->findnodes('alternatives/alternative'));
  $self->_register_zones($root->findvalue('zones/@base'),
			 $root->findnodes('zones/zone'));
  $self->_register_address_map(shift(@{$root->findnodes('address-map')}));
  $self->_register_iids($root->findnodes('interface-identifiers/iid'));

  ### Loop through the network declarations and process the hosts
  ### therein.
  for my $network_node
    ($root->findnodes('networks/network|networks/group/network')) {
    my $network_fqdn = $self->_fqdn_from_node($network_node);
    $self->_verbose("Processing network $network_fqdn\n");
    my $loc_node = shift(@{$network_node->findnodes('location')});
    my $network = IPAM::Network->new($network_node, $network_fqdn, $loc_node);
    eval { $self->{network_r}->add($network) }
      or $self->_die_at($network_node, $@);
    $network->location() and
      (eval { $self->{zone_r}->add_rr($network_fqdn, undef, 'LOC',
				      $network->location(), undef, 1,
				      IPAM::_nodeinfo($loc_node)) } or
       $self->_die_at($loc_node, $@));
    $network->description($network_node->findvalue('description'));
    $network->ttl($network_node->getAttribute('ttl'));

    ### Find all stub-prefixes associated with the network.  A network
    ### must have at least one prefix and can't have more than one IPv4
    ### prefix.
    my @network_prefixes =
      $self->{address_map}->lookup_by_id($network_fqdn, 1)
	or $self->_die_at($network_node, "Network ".$network->name()
			  ." is not associated with any prefixes\n");
    map { $network->add_prefix($_); $_->network($network) } @network_prefixes;
    eval { $network->set_tags($network_node->getAttribute('tag'),
			      @network_prefixes) }
      or $self->_die_at($network_node, $@);
    ($network->prefixes(undef, 4) <= 1) or
      $self->_die_at($network_node, "Network ".$network->name()
		     ." can't be associated with more than one IPv4"
		     ." prefix (found: "
		     .join(', ', map { $_->name() }
			   $network->prefixes(undef, 4)).")\n");

    foreach my $tag (qw/reserved generate host/) {
      foreach my $node ($network_node->findnodes($tag)) {
    	my $proc = "_process_".$tag."_node";
    	$self->$proc($node, $network);
      }
    }
  }

  ### Perform checks that require that the entire database
  ### has been read and parsed.

  ### Check if there are unreferenced IIDs.
  foreach my $iid ($self->{iid_r}->things()) {
    ($iid->use() and not $iid->in_use()) and
      $self->_warn_at($iid, "IPv6 IID ".$iid->ip()->addr().
		      ", assigned to host ".$iid->name().
		      ", isn't referenced anywhere");
  }

  ### Check if <hosted-on> targets exist
  foreach my $ref (@{$self->{hosted_on_check}}) {
    exists $self->{host_cache}{lc($ref->{target}->name())} or
      $self->_die_at($ref->{target},
		     $ref->{host}->name().": hosted-on host "
		     .$ref->{target}->name()." does not exist");
    }

  ### Check if "-admin" hosts exist without the host itself
  foreach my $admin (keys(%{$self->{admin_check}})) {
    my $ref = $self->{admin_check}{$admin};
    (exists $self->{host_cache}{lc($ref)} or
     exists $self->{alias_cache}{lc($ref)}) or
      $self->_warn_at($self->{host_cache}{lc($admin)},
		      "Console $admin: managed host $ref does not exist");
  }
}

### Return the name of the file and the line number within this file
### where a particular node is defined in the original XML file.
sub _nodeinfo($) {
  my ($node) = @_;
  defined $node or return();
  return($node->baseURI(), $node->line_number());
}

### Returns the value of a particular attribute of the given node if
### it exists or the default value if it doesn't.  The attribute value
### is converted to lower-case with lc().
sub _attr_with_default($$$) {
  my ($node, $attr, $default) = @_;
  my $value = $node->getAttribute($attr);
  return(defined $value ? lc($value) : $default);
}

### Shortcut for _attr_with_default for the 'ttl' attribute.
sub _ttl($$) {
  my ($node, $ttl) = @_;
  return(_attr_with_default($node, 'ttl', $ttl));
}

=item C<cache($file)>

  $ipam->cache($file);

Serialize the IPAM object to the given file.  This file can be passed
to the C<new_from_cache()> class method to reconstruct the database
without having to call the C<load()> method.

=cut

sub cache($$) {
  my ($self, $file) = @_;
  my $serializer = Data::Serializer::Raw->new(%serializer_opts);
  eval { $serializer->store($self, $file) } or
    die "Creation of cache file $file failed: $@";
}

####
#### Private instance methods
####

### Return a FQDN for a given name.  If the name ends with a dot, it
### is returned as is, otherwise the global domain suffix is added.
sub _fqdn($$) {
  my ($self, $name) = @_;
  return($name =~ /\.$/ ? $name : join('.', $name, $self->{domain}));
}

### Return a FQDN for a given name.  If the name ends with a dot, it
### is returned as is, otherwise the global domain suffix is added.
sub _fqdn_from_node($$) {
  my ($self, $node) = @_;
  return($self->_fqdn($node->getAttribute('name')));
}

sub _verbose($$) {
  my ($self, $msg) = @_;

  $self->{verbose} && print STDERR $msg;
}

### Determine file name and line number of the definition of a given
### IPAM::Thing or XML::LibXML::Node and add them to an error message
### to warn or die.
sub _at($$$$) {
  my ($self, $object, $msg, $warn) = @_;
  my ($file, $line);
  if ($object->isa('IPAM::Thing')) {
    ($file, $line) = $object->nodeinfo();
  } elsif ($object->isa('XML::LibXML::Node')) {
    ($file, $line) = _nodeinfo($object);
  } else {
    die "BUG: IPAM::_at(): unexpected object $object";
  }
  chomp $msg;
  defined $file and $msg = "$msg at $file, line $line";
  if ($warn) {
    $self->{warnings} and warn "Warning: $msg\n";
  } else {
    die "Error: $msg\n";
  }
}

### Wrappers for _at()
sub _warn_at($$$) {
  my ($self, $object, $msg) = @_;
  $self->_at($object, $msg, 1);
}

sub _die_at($$$) {
  my ($self, $object, $msg) = @_;
  $self->_at($object, $msg, undef);
}

sub _register_alternatives($@) {
  my ($self, @nodes) = @_;
  foreach my $node (@nodes) {
    my $label = $node->getAttribute('label');
    my $state = $node->getAttribute('state');
    my $alt = IPAM::Alternative->new($node, $label,
				     map { $_->textContent() }
				     $node->findnodes('allowed-state'));
    $alt->ttl($node->getAttribute('ttl'));
    eval { $alt->state($state) } or ($@ and $self->_die_at($node, $@));
    eval { $self->{alternative_r}->add($alt) } or $self->_die_at($node, $@);
 }
}

sub _check_alternative($$) {
  my ($self, $node) = @_;
  my ($active, $alt) = (1, undef);
  my ($label, $state);
  if (my $value = $node->getAttribute('alternative')) {
    (($label, $state) = split(':', $value)) == 2 or
      $self->_die_at($node, "Malformed alternative "
		     ."specifier ".'"'.$value.'"'."\n");
    $alt = $self->{alternative_r}->lookup($label) or
      $self->_die_at($node, "Unknown alternative ".'"'.$label.'"'."\n");
    $active = $alt->check_state($state);
    defined $active or
      $self->_die_at($node, 'Illegal state "'.$state.'"'
		     ." for alternative ".'"'.$label.'"'."\n");
  }
  return($active, $alt, $state);
}

### Populate the zone registry from the zone definitions.
sub _register_zones($$@) {
  my ($self, $base, @nodes) = @_;
  foreach my $node (@nodes) {
    my $name = $node->getAttribute('name');
    $name .= '.' unless $name =~ /\.$/;
    my $directory = $node->getAttribute('directory');
    $self->_verbose("Registering zone $name with directory $directory.\n");
    if ($directory) {
      $directory = join('/', $base, $directory) unless $directory =~ /^\//;
    }
    my $zone = eval { IPAM::Zone->new($node, $name, $directory) }
      or $self->_die_at($node, $@);
    eval { $self->{zone_r}->add($zone) } or $self->_die_at($node, $@);
    $zone->ttl(_ttl($node, $self->{ttl}));
  }
}

### Register address map
sub _register_address_map($$) {
  my ($self, $map_node) = @_;
  $self->_verbose("Registering address map\n");
  my $map = IPAM::AddressMap->new($map_node, 'Address Map');
  $self->{address_map} = $map;
  $self->_register_address_blocks($map->registry(),
				  $map_node->findnodes('block|net'));
}

### Recursively register all address blocks contained in a given
### block (i.e. prefix).  This also generates the DNS entries for
### all "stub-prefixes" (i.e. IP subnets).  Currently, blocks that
### are not stub-prefixes are not visible in the DNS.  In order to do that,
### we would have to have a method to define a prefix length for IPv6, which
### we don't (a NET-* AAAA always defines a /64).
sub _register_address_blocks($$@);
sub _register_address_blocks($$@) {
  my ($self, $prefix_upper, @nodes) = @_;
  foreach my $node (@nodes) {
    my $fqdn = $self->_fqdn_from_node($node);
    my $type = $node->nodeName();
    my $plen = $node->getAttribute('plen');
    $self->_verbose("Registering $type $fqdn\n");
    my $prefix = eval { IPAM::Prefix->new($node,
					  $node->getAttribute('prefix'),
					  $fqdn, $type eq 'net' ? 1 : 0) }
      or $self->_die_at($node, $@);
    $prefix->description($node->findvalue('description'));
    eval { $prefix->set_tags($node->getAttribute('tag'), $prefix_upper) }
      or $self->_die_at($node, $@);

    ## Stub nets have an implicit "plen" of the maximum value of
    ## the address family.  This is important for the ipam-free
    ## utility, which would otherwise aggregate addresses within
    ## a stub net.
    $type eq 'net' and $plen = $af_info{$prefix->af()}{max_plen};
    eval { $prefix->plen($plen) } or $self->_die_at($node, $@);
    eval { $prefix_upper->add($prefix) } or $self->_die_at($node, $@);
    if ($type eq 'net') {
      my @nodeinfo = IPAM::_nodeinfo($node);
      if ($prefix->af() == 4) {
	eval { $self->{zone_r}->add_rr($fqdn, undef, 'PTR',
				       $prefix->ip()->addr().'.',
				       undef, 1, @nodeinfo) } or
					 $self->_die_at($node, $@);
	eval { $self->{zone_r}->add_rr($fqdn, undef, 'A',
				       $prefix->ip()->mask(), undef, 1,
				       @nodeinfo) } or
					 $self->_die_at($node, $@);
      } else {
	eval { $self->{zone_r}->add_rr($fqdn, undef, 'AAAA',
				       $prefix->ip()->addr(), undef, 1,
				       @nodeinfo) } or
					 $self->_die_at($node, $@);
      }
    }
    $self->_register_address_blocks($prefix, $node->findnodes('block|net'));
  }
}

### Traverse a list of element nodes of type "iid" and populate the
### IID registry with IPAM::IID objects named by the fqdn of the host.
sub _register_iids($$@) {
  my ($self, @nodes) = @_;
  for my $node (@nodes) {
    my $id = $node->getAttribute('id');
    my $use = $node->getAttribute('use');
    if (defined $use and $use eq 'false') {
      $use = 0;
    } else {
      $use = 1;
    }
    my $fqdn = $self->_fqdn_from_node($node);
    my $iid = eval { IPAM::IID->new($node, $fqdn, $id) } or
      $self->_die_at($node, $@);
    eval { $self->{iid_r}->add($iid) } or $self->_die_at($node, $@);
    $iid->use($use);
    $self->_verbose("Registered IID $id for host $fqdn\n");
  }
}

### Process <reserved> element (IPv4 only).  The element can have
### any number of <block> elements that define prefixes, for which
### all covered addresses will be marked as reserved.  There are three
### types of default reserved addresses that can be selected through the
### "default" attribute
###   none    No default reserved addresses (only addresses covered
###           by <block> elements will be reserved).  This is useful
###           for loopback ranges which are technically stub nets but
###           don't have the network/broadcast limitation
###   minimal Only network and broadcast are reserved for stub nets
###           with prefixes shorter than /31
###   full    Like minimal, but in addition, a block of the lowest
###           addresses will be reserved, depending on the size of
###           the network (these addresses are used for router
###           interfaces, HSRP and other infrastructure stuff).
###             /32, /31: none
###             /30, /29: lowest address (router)
###             /28, /27, /26: 3 lowest addresses (router1,
###                                     router2, HSRP)
###             /25 and shorter: 7 lowest addresses
sub _process_reserved_node($$) {
  my ($self, $node, $network) = @_;
  ## Return immediately if this is a IPv6-only network.
  my $prefix = ($network->prefixes(undef, 4))[0] or return;
  my $plen = $prefix->ip()->masklen();
  my $default =  $node->getAttribute('default');
  defined $default or $default = 'full';
  if ($plen < 31 and $default ne 'none') {
    map {
      $self->_reserve($network, $node, $_->addr())
	->description('Network/Broadcast address')
      }
      ($prefix->ip()->network(), $prefix->ip()->broadcast());
    if ($default eq 'full') {
      my $max_reserve = 1;
      if ($plen >= 26 and $plen <= 28) {
	$max_reserve = 3;
      } elsif ($plen <= 25) {
	$max_reserve = 7;
      }
      for (my $i = 0; $i < $max_reserve; $i++) {
	$self->_reserve($network, $node, $prefix->ip()->nth($i)->addr())
	  ->description('Reserved for network equippment');
      }
    }
  }
  foreach my $block_node ($node->parentNode()->findnodes('reserved/block')) {
    $self->_process_block_node($block_node, $prefix,
			       sub { $self->_reserve($network, $_[0], $_[1]) });
  }
}

### Helper method for _process_reserved()
sub _reserve($$$) {
  my ($self, $network, $reserved_node, $addr) = @_;
  $self->_verbose("Marking $addr as reserved\n");
  my $address = eval { IPAM::Address->new($reserved_node, $addr, 1) }
    or $self->_die_at($reserved_node, $@);
  eval { $network->add_address($address) }
    or $self->_die_at($reserved_node, $@);
  $address->description($reserved_node->findvalue('description'));
  return($address);
}

sub _process_generate_node($$$) {
  my ($self, $node, $network) = @_;
  my $prefix = ($network->prefixes(undef, 4))[0];
  my $pattern = $node->getAttribute('pattern');
  my $desc = $node->findvalue('description');
  my $ttl = $node->getAttribute('ttl');
  my $i = 1;
  foreach my $block_node ($node->findnodes('block')) {
    $self->_process_block_node
      ($block_node, $prefix,
       sub { my ($block_node, $addr) = @_;
	     (my $name = $pattern) =~ s/%n/$i/;
	     $i++;
	     my $block_desc = $block_node->findvalue('description');
	     $self->_process_host_node
	       ($self->_synthesize_host_node
		($name, $ttl, $block_desc ? $block_desc : $desc, $addr),
		$network, $node, $block_node);
	   });
  }
}

### Synthesize a <host> element given a FQDN, TTL, description and
### IPv4 address.  Returns a XML::LibXML::Element that can be passed
### directly to _process_host_node() for integration into the IPAM.
sub _synthesize_host_node($$$) {
  my ($self, $name, $ttl, $desc, $v4addr) = @_;
  my $host = XML::LibXML::Element->new('host');
  $host->setAttribute('name', $name);
  $ttl and $host->setAttribute('ttl', $ttl);
  my $chunk = ($desc ? "<description>$desc</description>" : '')
    ."<ip><v4><a>$v4addr</a></v4></ip>";
  $host->appendWellBalancedChunk($chunk);
  return($host);
}

### Helper method for _process_{reserved,generate}_node()
sub _process_block_node($$$$) {
  my ($self, $block_node, $prefix, $callback) = @_;
  my $prefix_r = eval {
    IPAM::Prefix->new($block_node,
		      $block_node->getAttribute('prefix'), 0)
    } or $self->_die_at($block_node, $@);
  $prefix_r->af() == 4 or
    $self->_die_at($block_node, "Address block must be IPv4\n");
  foreach my $ip (@{$prefix_r->ip()->splitref(32)}) {
    ## Ignore overlap with the broadcast address
    next if $ip->addr() eq $prefix->ip()->broadcast()->addr();
    $callback->($block_node, $ip->addr());
  }
}

sub _process_host_node($$$$) {
  my ($self, $node, $network, $gen_node, $gen_block_node) = @_;
  my $host_fqdn = $self->_fqdn_from_node($node);
  $self->_verbose("Processing host $host_fqdn\n");
  ## If this host is derived from a synthesized <host> element, record
  ## the node of the corresponding <generate> element as origin node.
  my $host = IPAM::Host->new($gen_node ? $gen_node : $node,
			     $host_fqdn, $network);
  $host->description($node->findvalue('description'));
  eval { $host->set_tags($node->getAttribute('tag'), $network) }
    or $self->_die_at($node, $@);
  eval { $network->add_host($host) } or $self->_die_at($node, $@);
  ## If the host has no TTL, inherit the TTL from the network,
  ## otherwise inherit from the zone
  my ($zone) = $self->{zone_r}->lookup_fqdn($host_fqdn);
  defined $zone or
    $self->_die_at($node, $host->name()
		   .": the hostname cannot be associated with any "
		   ."configured zone\n");
  my $zone_ttl = $zone->ttl();
  my $network_ttl = $network->ttl();
  my $default_ttl = $network_ttl ? $network_ttl : $zone_ttl;
  $host->ttl(_ttl($node, $default_ttl));
  if (my ($admin_ref, $domain) = ($host_fqdn =~ /^(\w+)-admin\.(.*)$/i)) {
    $self->{admin_check}{$host_fqdn} = join('.', $admin_ref, $domain);
  }

  ### Default values should be set by the "a:defaultValue"
  ### annotations in the schema, but I don't know how that
  ### is supposed to work.  Maybe it's just not supported by
  ### the RelaxNG validator used by XML::LibXML.
  if ($node->hasAttribute('dns')) {
    $host->dns($node->find('@dns[.=string(true())]')->size() != 0);
  } else {
    $host->dns(1);
  }
  my $ip_node = shift(@{$node->findnodes('ip')});
  my $canonical = 'true';
  my $reverse = 'true';
  if ($ip_node->hasAttribute('canonical-name')) {
    $canonical = _attr_with_default($ip_node, 'canonical-name',
				    undef);
  }
  if ($ip_node->hasAttribute('reverse-dns')) {
    $reverse = _attr_with_default($ip_node, 'reverse-dns',
				  undef);
  }
  ## The hosts' TTL is overriden by the ip's TTL
  my $addr_ttl = _ttl($ip_node, $host->ttl());

  foreach my $af_node ($ip_node->findnodes('*')) {
    my @addrs;
    my $af = $af_tag_to_version{$af_node->nodeName()};
    my $canonical_af = _attr_with_default($af_node, 'canonical-name',
					  $canonical);
    my $reverse_af = _attr_with_default($af_node, 'reverse-dns', $reverse);
    ## The ip's TTL is overriden by af-specific TTLs.
    my $af_ttl = _ttl($af_node, $addr_ttl);
    if ($af == 6 and (not $af_node->hasAttribute('from-iid') or
		      not $af_node->find('@from-iid[.=string(false())]'))) {
      my @iid_lookup_fqdns;
      push(@iid_lookup_fqdns, $host_fqdn);
      unless ($af_node->find('@from-iid[.=string(true())]') or
	      not $af_node->hasAttribute('from-iid')) {
	### from-iid specifies a name or several names separated by
	### ':', from which to copy the IID.  In that case, the host
	### must not have its own IID.
	my $iid = $self->{iid_r}->lookup($host_fqdn);
	$iid and
	  $self->_die_at($af_node, "$host_fqdn: Synthesizing of IPv6 "
			 ."address from IID failed: references "
			 ."$host_fqdn but has its own IID "
			 ."(".$iid->ip()->addr().")\n");
	@iid_lookup_fqdns = map { $self->_fqdn($_) }
	  split(':', $af_node->getAttribute('from-iid'));
      }
      foreach my $iid_lookup_fqdn (@iid_lookup_fqdns) {
	if (my $iid = $self->{iid_r}->lookup($iid_lookup_fqdn)) {
	  if ($iid->use()) {
	    ### Construct a IPv6 address from the host's IID for all
	    ### the network's prefixes.
	    $self->_verbose("Synthesizing IPv6 address for $host_fqdn "
			    ."from IID.\n");
	    foreach my $prefix ($network->prefixes(undef, $af)) {
	      my $ip = $prefix->ip();
	      $ip->masklen() == 64 or
		$self->_die_at($ip_node, "$host_fqdn: Synthesizing of "
			       ."IPv6 address from IID failed: requires "
			       ."a /64, but conflicts with $af "
			       . $prefix->name());
	      my ($active, $alt, $state) =
		$self->_check_alternative($af_node);
	      push(@addrs, { af => $af,
			     text => ipv6_n2x((add128($ip->aton(),
						      $iid->ip()->aton()))[1]),
			     node => $af_node,
			     canonical => $canonical_af,
			     reverse => $canonical_af eq 'true' ?
			     $reverse_af : 'false',
			     alt => [ $alt, $state ],
			     dns => $host->dns() && $active});
	      $iid->in_use(1);
	    }
	  }
	} elsif ($iid_lookup_fqdn ne $host_fqdn) {
	  $self->_die_at($af_node, "$host_fqdn: Synthesizing of IPv6 "
			 ."address from IID failed: references "
			 ."$iid_lookup_fqdn, which has no IID.");
	}
      }
    }

    foreach my $a_node ($af_node->findnodes('a')) {
      my $canonical_a = _attr_with_default($a_node, 'canonical-name',
					   $canonical_af);
      my $reverse_a = _attr_with_default($a_node, 'reverse-dns',
					 $reverse_af);
      $canonical_a eq 'false' and $reverse_a = 'false';
      my $dns_a = _attr_with_default($a_node, 'dns', 'true');
      my ($active, $alt, $state) = $self->_check_alternative($a_node);
      push(@addrs, { af => $af,
		     text => $a_node->textContent(),
		     node => $a_node,
		     canonical => $canonical_a,
		     reverse => $reverse_a,
		     alt => [ $alt, $state ],
		     dns => ($host->dns() && $dns_a eq 'true') && $active});
    }

    foreach my $addr (@addrs) {
      ## If this host node has been synthesized from a <generate>,
      ## the node object of the address is some temporary thing which
      ## is not visible by the user.  In this case, we subsitute the
      ## node of the <block> element within the <generate> from which
      ## the address has been synthesized.
      $gen_block_node and $addr->{node} = $gen_block_node;
      my $address = eval {
	IPAM::Address->new($addr->{node}, $addr->{text})
	} or $self->_die_at($addr->{node}, $@);
      unless ($address->af() == $addr->{af}) {
	$self->_die_at($addr->{node}, $address->name." is not a valid "
		       .$af_info{$addr->{af}}{name}." address.\n");
      }
      if (exists $self->{address_cache}{$address->name()}) {
	$address = $self->{address_cache}{$address->name()};
      } else {
	eval { $network->add_address($address) } or
	  $self->_die_at($addr->{node}, $@);
	$self->{address_cache}{$address->name()} = $address;
      }
      eval { $host->add_address($address) } or
	$self->_die_at($addr->{node}, $@);
      my ($alt, $state) = @{$addr->{alt}};
      my $rr_ttl = $af_ttl;
      if ($alt) {
	$alt->add_mapping($state, IPAM::Alternative::MAP_ADDRESS,
			  $host, $address);
	defined $alt->ttl() and $rr_ttl = $alt->ttl();
      }
      $addr->{canonical} eq 'true' and
	(eval { $address->canonical_host($host) } or
	 $self->_die_at($addr->{node}, $@));
      eval { $address->add_host($host) } or $self->_die_at($addr->{node}, $@);
      my $rrtype = $af_info{$addr->{af}}{rrtype};
      eval { $self->{zone_r}->add_rr($host_fqdn, $rr_ttl,
				     $rrtype, $address->name(),
				     $addr->{reverse} eq 'true' ?
				     undef : "secondary $rrtype RR",
				     $addr->{dns},
				     IPAM::_nodeinfo($addr->{node})) } or
				       $self->_die_at($af_node, $@);
    }
  } # foreach $af_node

  $host->address_registry->counter() or
    $self->_warn_at($host, "There are no addresses associated with "
		    ."the host ".$host->name());

  if (my $loc = $network->location() and not
      $node->find('@noloc[.=string(true())]')) {
    eval { $self->{zone_r}->add_rr($host_fqdn, undef, 'LOC',
				   $loc, undef, $host->dns(),
				   $network->location_nodeinfo()) } or
				     $self->_die_at($node, $@);
  }

  foreach my $alias_node ($node->findnodes('alias')) {
    my $alias_fqdn = $self->_fqdn_from_node($alias_node);
    $self->_verbose("Registering host $alias_fqdn as alias for "
		    ."$host_fqdn\n");
    my $alias = IPAM::Thing->new($alias_node, $alias_fqdn);
    ## The host's TTL is overriden by the alias' TTL
    $alias->ttl(_ttl($alias_node, $host->ttl()));
    eval { $host->add_alias($alias) } or $self->_die_at($alias_node, $@);
    my ($active, $alt, $state) = $self->_check_alternative($alias_node);
    if ($alt) {
      $alt->add_mapping($state, IPAM::Alternative::MAP_ALIAS,
			$host, $alias);
      defined $alt->ttl() and $alias->ttl($alt->ttl());
    }
    eval { $self->{zone_r}->add_rr($alias_fqdn, $alias->ttl(),
				   'CNAME', $host_fqdn,
				   undef, $host->dns() && $active,
				   IPAM::_nodeinfo($alias_node)) } or
				     $self->_die_at($alias_node, $@);
    $self->{alias_cache}{lc($alias_fqdn)} = $host;
  }

  foreach my $hosted_on_node ($node->findnodes('hosted-on')) {
    my $hosted_on_fqdn = $self->_fqdn_from_node($hosted_on_node);
    $self->_verbose("Registering host $hosted_on_fqdn as hosted-on for "
		    ."$host_fqdn\n");
    my $hosted_on = IPAM::Thing->new($hosted_on_node, $hosted_on_fqdn);
    ## The host's TTL is overriden by the hosted_on's TTL
    $hosted_on->ttl(_ttl($hosted_on_node, $host->ttl()));
    eval { $host->add_hosted_on($hosted_on) }
      or $self->_die_at($hosted_on_node, $@);
    if (not $hosted_on_node->hasAttribute('check') or
	$hosted_on_node->find('@check[.=string(true())]')) {
      push(@{$self->{hosted_on_check}},
	   { host => $host, target => $hosted_on });
    }
    eval { $self->{zone_r}->add_rr($host_fqdn, $hosted_on->ttl(),
				   'PTR', $hosted_on_fqdn, undef, $host->dns(),
				   IPAM::_nodeinfo($hosted_on_node)) } or
				     $self->_die_at($hosted_on_node, $@);
  }

  foreach my $rr_node ($node->findnodes('rr')) {
    my $type = $rr_node->getAttribute('type');
    (my $rdata = $rr_node->textContent()) =~ s/^\s*(.*?)\s*$/$1/;
    my ($active, $alt, $state) = $self->_check_alternative($rr_node);
    my $rr_ttl = _ttl($rr_node, $host->ttl());
    if ($alt) {
      $alt->add_mapping($state, IPAM::Alternative::MAP_RR,
			$host, { type => $type, ttl => $rr_ttl, rdata => $rdata,
				 nodeinfo => [ IPAM::_nodeinfo($rr_node) ]});
      defined $alt->ttl() and $rr_ttl = $alt->ttl();
    }
    ## The hosts's TTL is overriden by the RR's TTL
    $self->{zone_r}->add_rr($host_fqdn, $rr_ttl, $type, $rdata, undef,
			    $host->dns && $active, IPAM::_nodeinfo($rr_node));
  }
  $self->{host_cache}{lc($host->name())} = $host;
}

####
#### Public instance methods
####

=item address_map()

my $map = $ipam->address_map();

Returns the L<IPAM::AddressMap> object of the IPAM database.

=cut

### Return the address map.
sub address_map($) {
  my ($self) = @_;
  return($self->{address_map});
}

=item C<registry($reg)>

  my $r = $ipam->registry($reg);

Returns the registry object associated with the identifier $reg, which
can be one of

IPAM::REG_IID
IPAM::REG_ZONE
IPAM::REG_NETWORK
IPAM::REG_ALTERNATIVE

=cut

### Return the IPAM::Registry objects for one of the registries defined
### by the IPAM::REG_* constants.
sub registry($$) {
  my ($self, $registry) = @_;
  exists $registries{$registry} or return(undef);
  return($self->{$registries{$registry}{key}});
}

=item C<nameinfo($fqdn)>

  my $info = $ipam->nameinfo($fqdn);

Returns a reference to a hash with the following keys

=over 4

=item zone

L<IPAM::Zone> object whose name exactly matches $fqdn.

=item iid

L<IPAM::IID> object whose name exactly matches $fqdn.

=item network

List of L<IPAM::Network> objects whose names exactly match $fqdn.

=item block

List of L<IPAM::Prefix> objects that define network blocks or stub
networks in the address map whose id attribute matches $fqdn.

=item host

List of L<IPAM::Host> objects whose names exactly match $fqdn.

=item alias

L<IPAM::Host> object of the alias' canonical name, if $fqdn is an alias.

=back

=back

=cut

sub nameinfo($$) {
  my ($self, $fqdn) = @_;
  my %info;
  foreach my $reg (keys(%registries)) {
    $info{$reg} = $self->{$registries{$reg}{key}}->lookup($fqdn);
  }
  push(@{$info{block}}, $self->{address_map}->lookup_by_id($fqdn));
  push(@{$info{host}}, $self->{network_r}->find_host($fqdn));
  push(@{$info{alias}}, $self->{network_r}->find_alias($fqdn));
  return(\%info);
}

1;
