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

A stub network is a special case of a network block and is used to
designate a proper IP subnet, which does not contain any more-specific
network blocks.  If the address map is viewed as a tree, only the
leave nodes of it can be marked as stub networks (but a leave node
does not have to describe a stub network).

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

=item Stub Networks

In an IPv6 environment, a stub network can have any number of prefixes
(at most one IPv4 and any number of IPv6 but at least one of any
kind).  The name of a stub network collects all prefixes that make up
a single IP subnet.

=back

=item IPv6 Interface Identifier Registry

This registry contains a mapping of interface identifiers to DNS host names.

=item Stub Network Definition

The address map defines all stub networks that are contained in the
managed address space.  Each stub network is mapped to a number of
prefixes as described above.  The addresses covered by these prefixes
can be assigned to host names in this section of the IPAM database.

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

All DNS names in the database are fully qualified (FQDN - fully
qualified domain name).  In order to create fragments of DNS master
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
use IPAM::Thing;
use IPAM::Registry;
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
	     };

my %default_options = ( verbose => undef,
			base_dir => '.',
			validate => undef);
my $schema_file = 'schemas/ipam.rng';
my %af_tag_to_version = ( v4 => 4, v6 => 6 );
my %registries = ( IPAM::REG_ZONE => { key => 'zone_r',
				       module => 'IPAM::Zone::Registry' },
		   IPAM::REG_IID => {key => 'iid_r',
				     module => 'IPAM::IID::Registry' },
		   IPAM::REG_NETWORK => { key => 'network_r',
					  module => 'IPAM::Network::Registry' },
		 );

=head1 CLASS METHODS

=over 4

=item new()

my $ipam = IPAM->new();

Create an instance of a IPAM object.

=back

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

=head1 INSTANCE METHODS

=over 4

=item load($file)

$ipam->load($file) or die;

Load the IPAM database from the given file.

=cut

sub load($$) {
  my ($self, $file) = @_;
  my (%host_cache, %alias_cache, @hosted_on_check, %admin_check);
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

  ### Add the name of $file to the DOM as an element node called 'file'
  ### with attribute name="$file".  This allows _nodeinfo() to access the
  ### top-level file name from the DOM alone.
  my $root = $ipam->getDocumentElement();
  my $file_element = $ipam->createElement('file');
  $file_element->setAttribute('name', $file);
  $root->appendChild($file_element);

  my $xpc = XML::LibXML::XPathContext->new($root) or
    die "Can't create XPath context: $!";
  my $domain = $xpc->findvalue('domain');
  $domain .= '.' unless $domain =~ /\.$/;

  ## The TTL can be overriden by various lower-level elements that carry
  ## a "ttl" attribute.  Also See the _ttl() helper function.
  my $ttl = $xpc->findvalue('ttl');

  ### Create registries
  map { $self->{$registries{$_}{key}} = $registries{$_}{module}->new() }
    keys(%registries);

  _register_zones($self, $xpc->findvalue('zones/@base'),
		  $xpc->findnodes('zones/zone'));
  _register_address_map($self, $ttl, $domain,
			($xpc->findnodes('address-map'))[0]);
  _register_iids($self, $domain,
		 $xpc->findnodes('interface-identifiers/iid'));

  ### Loop through the network declarations and process the hosts
  ### therein.
  for my $network_node 
    ($xpc->findnodes('networks/network|networks/group/network')) {
    my %address_cache;
    $xpc->setContextNode($network_node);
    my ($network_fqdn, $network_ttl) = _fqdn_ttl($network_node, $ttl, $domain);
    _verbose($self, "Processing network $network_fqdn\n");

    ## This TTL is used for all LOC records derived from the network's
    ## location element.
    my $loc_ttl = $network_ttl;
    my $loc_node = ($xpc->findnodes('location'))[0];
    my $location = $xpc->findvalue('location');
    my $network = IPAM::Network->new($network_node, $network_fqdn, $location);
    eval { $self->{network_r}->add($network) } or
      _die_at_node($network_node, $@);
    $location and
      (eval { $self->{zone_r}->add_rr($loc_node, $network_fqdn, $loc_ttl, 'LOC',
				      $location, undef, 1) } or
       _die_at_node($loc_node, $@));
    $network->description($xpc->findvalue('description'));

    ### Find all stub-prefixes associated with the network.  A network
    ### must have at least one prefix and can't have more than one IPv4
    ### prefix.
    my @network_prefixes =
      $self->{address_map}->lookup_by_id($network_fqdn, 1)
	or _die_at_node($network_node, "Network ".$network->name()
			." is not associated with any prefixes\n");
    map { $network->add_prefix($_); $_->network($network) } @network_prefixes;
    my ($v4p, $v6p) = (scalar($network->prefixes(undef, 4)),
		       scalar($network->prefixes(undef, 6)));
    ($v4p <= 1) or
      _die_at_node($network_node, "Network ".$network->name()
		   ." can't be associated with more than one IPv4 prefix "
		   ." (found: "
		   .join(', ', map { $_->name() }
			 $network->prefixes(undef, 4))
		   .")\n");

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
    if ($v4p) {
      my $prefix = ($network->prefixes(undef, 4))[0];
      my $reserved_node = ($xpc->findnodes('reserved'))[0];
      my $plen = $prefix->ip()->masklen();
      my $default =  $reserved_node->getAttribute('default');
      defined $default or $default = 'full';
      if ($plen < 31 and $default ne 'none') {
	map { _reserve($self, $network, $reserved_node, $_->addr()) }
	  ($prefix->ip()->network(), $prefix->ip()->broadcast());
	if ($default eq 'full') {
	  my $max_reserve = 1;
	  if ($plen >= 26 and $plen <= 28) {
	    $max_reserve = 3;
	  } elsif ($plen <= 25) {
	    $max_reserve = 7;
	  }
	  for (my $i = 0; $i < $max_reserve; $i++) {
	    _reserve($self, $network, $reserved_node,
		     $prefix->ip()->nth($i)->addr());
	  }
	}
      }
      foreach my $block_node ($xpc->findnodes('reserved/block')) {
	my $prefix = eval {
	  IPAM::Prefix->new($block_node,
			    $block_node->getAttribute('prefix'), 0)
	  } or _die_at_node($block_node, $@);
	$prefix->af() == 4 or
	  _die_at_node($block_node,
		       "Reserved address block must be IPv4\n");
	foreach my $ip (@{$prefix->ip()->splitref(32)}) {
	  _reserve($self, $network, $block_node, $ip->addr());
	}
      }
    }

    foreach my $host_node ($xpc->findnodes('host')) {
      $xpc->setContextNode($host_node);
      my ($host_fqdn, $host_ttl) = _fqdn_ttl($host_node, $network_ttl, $domain);
      _verbose($self, "Processing host $host_fqdn\n");
      my $host = IPAM::Host->new($host_node, $host_fqdn, $network);
      eval { $network->add_host($host) } or _die_at_node($host_node, $@);
      $host->description($xpc->findvalue('description'));
      if (my ($admin_ref, $domain) = ($host_fqdn =~ /^(\w+)-admin\.(.*)$/i)) {
	$admin_check{$host_fqdn} = join('.', $admin_ref, $domain);
      }

      ### Default values should be set by the "a:defaultValue"
      ### annotations in the schema, but I don't know how that
      ### is supposed to work.  Maybe it's just not supported by
      ### the RelaxNG validator used by XML::LibXML.
      if ($host_node->hasAttribute('dns')) {
	$host->dns($xpc->find('@dns[.=string(true())]'));
      } else {
	$host->dns(1);
      }
      my $ip_node = ($xpc->findnodes('ip'))[0];
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
      my $addr_ttl = _ttl($ip_node, $host_ttl);

      foreach my $af_node ($xpc->findnodes('*', $ip_node)) {
	my @addrs;
	my $af = $af_tag_to_version{$af_node->nodeName()};
	my $canonical_af = _attr_with_default($af_node, 'canonical-name',
					      $canonical);
	my $reverse_af = _attr_with_default($af_node, 'reverse-dns', $reverse);
	my $af_ttl = _ttl($af_node, $addr_ttl);
	if ($af == 6 and (not $af_node->hasAttribute('from-iid') or
	    not $xpc->find('@from-iid[.=string(false())]', $af_node))) {
	  my $iid_lookup_fqdn = $host_fqdn;
	  unless ($xpc->find('@from-iid[.=string(true())]', $af_node) or
		  not $af_node->hasAttribute('from-iid')) {
	    ### from-iid specifies a name from which to copy the IID.
	    ### In that case, the host must not have its own IID.
	    my $iid = $self->{iid_r}->lookup($host_fqdn);
	    $iid and
	      _die_at_node($af_node, "$host_fqdn: Synthesizing of IPv6 "
			   ."address from IID failed: references "
			   ."$iid_lookup_fqdn but has its own IID "
			   ."(".$iid->ip()->addr().")\n");
	    $iid_lookup_fqdn = _fqdn($af_node->getAttribute('from-iid'),
				     $domain);
	  }
	  if (my $iid = $self->{iid_r}->lookup($iid_lookup_fqdn)) {
	    if ($iid->use()) {
	      ### Construct a IPv6 address from the host's IID for all
	      ### the network's prefixes.
	      _verbose($self, "Synthesizing IPv6 address for $host_fqdn "
		       ."from IID.\n");
	      foreach my $prefix ($network->prefixes(undef, $af)) {
		my $ip = $prefix->ip();
		$ip->masklen() == 64 or
		  _die_at_node($ip_node,
			       "$host_fqdn: Synthesizing of IPv6 address "
			       ."from IID failed: requires a /64, but "
			       ."conflicts with $af ". $prefix->name());
		push(@addrs, { af => $af,
			       text => ipv6_n2x((add128($ip->aton(),
							$iid->ip()->aton()))[1]),
			       node => $af_node,
			       canonical => $canonical_af,
			       reverse => $canonical_af eq 'true' ?
			       $reverse_af : 'false' });
		$iid->in_use(1);
	      }
	    }
	  } elsif ($iid_lookup_fqdn ne $host_fqdn) {
	    _die_at_node($af_node, "$host_fqdn: Synthesizing of IPv6 address "
			 ."from IID failed: references $iid_lookup_fqdn, "
			 ."which has no IID.");
	  }
	}

	foreach my $a_node ($xpc->findnodes('a', $af_node)) {
	  my $canonical_a = _attr_with_default($a_node, 'canonical-name',
					       $canonical_af);
	  my $reverse_a = _attr_with_default($a_node, 'reverse-dns',
					     $reverse_af);
	  $canonical_a eq 'false' and $reverse_a = 'false';
	  my $dns_a = _attr_with_default($a_node, 'dns', 'true');
	  push(@addrs, { af => $af,
			 text => $a_node->textContent(),
			 node => $a_node,
			 canonical => $canonical_a,
			 reverse => $reverse_a,
			 dns => ($host->dns() and $dns_a eq 'true') });
	}

	foreach my $addr (@addrs) {
	  my $address = eval {
	    IPAM::Address->new($addr->{node}, $addr->{text})
	    } or _die_at_node($addr->{node}, $@);
	  unless ($address->af() == $addr->{af}) {
	    my ($file, $line) = _nodeinfo($addr->{node});
	    _die_at_node($addr->{node}, $address->name." is not a valid "
			 .$af_info{$addr->{af}}{name}." address.\n");
	  }
	  if (exists $address_cache{$address->name()}) {
	    $address = $address_cache{$address->name()};
	  } else {
	    eval { $network->add_address($address) } or
	      _die_at_node($addr->{node}, $@);
	    $address_cache{$address->name()} = $address;
	  }
	  eval { $host->add_address($address) } or
	    _die_at_node($addr->{node}, $@);
	  $addr->{canonical} eq 'true' and
	    (eval { $address->canonical_host($host) } or
	     _die_at_node($addr->{node}, $@));
	  eval { $address->add_host($host) } or
	    _die_at_node($addr->{node}, $@);
	  my $rrtype = $af_info{$addr->{af}}{rrtype};
	  eval { $self->{zone_r}->add_rr($addr->{node}, $host_fqdn, $af_ttl,
					 $rrtype, $address->name(),
					 $addr->{reverse} eq 'true' ?
					 undef : "secondary $rrtype RR",
					 $addr->{dns}) } or
					   _die_at_node($af_node, $@);
	}
      } # foreach $af_node

      $host->address_registry->counter() or
	_warn_at_node($host->node(), "There are no addresses associated with "
	  ."the host ".$host->name());

      if (my $loc = $network->location() and not
	  $xpc->find('@noloc[.=string(true())]')) {
	eval { $self->{zone_r}->add_rr($loc_node, $host_fqdn, $loc_ttl, 'LOC',
				       $loc, undef, $host->dns()) } or
					 _die_at_node($host_node, $@);
      }

      foreach my $alias_node ($xpc->findnodes('alias')) {
	my ($alias_fqdn, $alias_ttl) = _fqdn_ttl($alias_node, $host_ttl,
						 $domain);
	_verbose($self, "Registering host $alias_fqdn as alias for "
		 ."$host_fqdn\n");
	eval { $host->add_alias(IPAM::Thing->new($alias_node, $alias_fqdn)) }
	  or _die_at_node($alias_node, $@);
	eval { $self->{zone_r}->add_rr($alias_node, $alias_fqdn, $alias_ttl,
				       'CNAME', $host_fqdn,
				       undef, $host->dns()) } or
					 _die_at_node($alias_node, $@);
	$alias_cache{lc($alias_fqdn)} = $host;
      }

      foreach my $hosted_on_node ($xpc->findnodes('hosted-on')) {
	my ($hosted_on_fqdn, $hosted_on_ttl) = _fqdn_ttl($hosted_on_node,
							 $host_ttl, $domain);
	_verbose($self, "Registering host $hosted_on_fqdn as hosted-on for "
		 ."$host_fqdn\n");
	my $hosted_on = IPAM::Thing->new($hosted_on_node, $hosted_on_fqdn);
	eval { $host->add_hosted_on($hosted_on) }
	  or _die_at_node($hosted_on_node, $@);
	if (not $hosted_on_node->hasAttribute('check') or
	    $xpc->find('@check[.=string(true())]', $hosted_on_node)) {
	  push(@hosted_on_check, { host => $host, target => $hosted_on });
	}
	eval { $self->{zone_r}->add_rr($hosted_on_node, $host_fqdn,
				       $hosted_on_ttl,
				       'PTR', $hosted_on_fqdn,
				       undef, $host->dns()) } or
					 _die_at_node($hosted_on_node, $@);
      }

      foreach my $rr_node ($xpc->findnodes('rr')) {
	my $type = $rr_node->getAttribute('type');
	my $rr_ttl = _ttl($rr_node, $host_ttl);
	(my $rdata = $rr_node->textContent()) =~ s/^\s*(.*?)\s*$/$1/;
	$self->{zone_r}->add_rr($rr_node, $host_fqdn, $rr_ttl, $type,
				$rdata, undef, $host->dns);
      }
      $host_cache{lc($host_fqdn)} = $host;
    }
  }

  ### Check if there are unreferenced IIDs.
  foreach my $iid ($self->{iid_r}->things()) {
    ($iid->use() and not $iid->in_use()) and
      _warn_at_node($iid->node(), "IPv6 IID ".$iid->ip()->addr().
		    ", assigned to host ".$iid->name().
		    ", isn't referenced anywhere");
  }

  ### Check if <hosted-on> targets exist
  foreach my $ref (@hosted_on_check) {
    exists $host_cache{lc($ref->{target}->name())} or
      _die_at_node($ref->{target}->node(),
		   $ref->{host}->name().": hosted-on host "
		   .$ref->{target}->name()." does not exist");
    }

  ### Check if "-admin" hosts exist without the host itself
  foreach my $admin (keys(%admin_check)) {
    my $ref = $admin_check{$admin};
    (exists $host_cache{lc($ref)} or exists $alias_cache{lc($ref)}) or
      _warn_at_node($host_cache{lc($admin)}->node(),
		   "Console $admin: managed host $ref does not exist");
  }
}

sub _verbose($$) {
  my ($self, $msg) = @_;

  $self->{verbose} && print STDERR $msg;
}

sub _reserve($$$) {
  my ($self, $network, $reserved_node, $addr) = @_;
  _verbose($self, "Marking $addr as reserved\n");
  my $address = eval { IPAM::Address->new($reserved_node, $addr, 1) }
    or _die_at_node($reserved_node, $@);
  eval { $network->add_address($address) }
    or _die_at_node($reserved_node, $@);
}

### Return the name of the file and the line number within this file
### where a particular node is defined in the original XML file.
###
### Moves up the DOM tree looking for an <include> tag to determine
### whether the definition of a particular node is part of a file that
### has been treated by XInclude.  If found, the name of the file is
### extracted from the "href" attribute and returned to the caller.
### Otherwise, the top-level file is returned (the name of that file
### has been added as a <file> element by IPAM::load() to be
### accessible through the DOM).
###
### During XInclude processing, a pair of <include> elements are added
### just before (previous sibling) and after (next sibling) the
### top-level included element.  The former has an attribute called
### "href" which is a copy of the attribute of the original
### <xi:include> element.  The latter <include> element has no
### attributes.  We need to find the closest enclosing include while
### skipping includes that cover a sibling element. Note that these
### "include" elements are not accessible by XPath.
sub _nodeinfo($) {
  my ($node) = @_;
  defined $node or return(undef, undef);
  my ($file, $path) = fileparse($node->findvalue('/ipam-base/file/@name'));
  my $line = $node->line_number();

 NODE:
  while ($node) {
    my $sibling = $node;
    my $skip = 0;
    while ($sibling = $sibling->previousSibling()) {
      next unless ($sibling->nodeName() eq 'include');
      if ($skip) {
	$skip = 0;
	next;
      }
      foreach my $attr ($sibling->attributes()) {
	if ($attr->nodeName() eq 'href') {
	  $file = $attr->nodeValue();
	  last NODE;
	}
      }
      ## We've entered an include that covers a sibling node from
      ## "below".  We need to ignore the matching include element that
      ## contains the href for it.
      $skip = 1;
    }
  } continue {
    $node = $node->parentNode();
  }
  return($path.$file, $line);
}

### Determine file name and line number of the definition of a given
### node and add them to an error message to die.
sub _at_node($$$) {
  my ($node, $msg, $warn) = @_;
  my ($file, $line) = _nodeinfo($node);
  chomp $msg;
  defined $file and $msg = "$msg at $file, line $line";
  $warn ? warn "Warning: $msg\n" : die "Error: $msg\n";
}

sub _warn_at_node($$) {
  my ($node, $msg) = @_;
  _at_node($node, $msg, 1);
}

sub _die_at_node($$) {
  my ($node, $msg) = @_;
  _at_node($node, $msg, undef);
}

### Return a FQDN for a given name.  If the name ends with a dot, it
### is returned as is, otherwise the given domain suffix is added.
sub _fqdn($$) {
  my ($name, $domain) = @_;
  return($name =~ /\.$/ ? $name : join('.', $name, $domain));
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

### Combination of _fqdn and _ttl.
sub _fqdn_ttl($$$) {
  my ($node, $ttl, $domain) = @_;
  return(_fqdn($node->getAttribute('name'), $domain),
	 _attr_with_default($node, 'ttl', $ttl));
}

### Populate the zone registry from the zone definitions.
sub _register_zones($$@) {
  my ($self, $base, @nodes) = @_;
  foreach my $node (@nodes) {
    my $name = $node->getAttribute('name');
    $name .= '.' unless $name =~ /\.$/;
    my $directory = $node->getAttribute('directory');
    _verbose($self, "Registering zone $name with directory $directory.\n");
    unless ($directory eq 'IGNORE') {
      $directory = join('/', $base, $directory) unless $directory =~ /^\//;
    }
    my $zone = IPAM::Zone->new($node, $name, $directory);
    eval { $self->{zone_r}->add($zone) } or _die_at_node($node, $@);
  }
}

### Recursively register all address blocks contained in a given
### block (i.e. prefix).  This also generates the DNS entries for
### all "stub-prefixes" (i.e. IP subnets).  Currently, blocks that
### are not stub-prefixes are not visible in the DNS.  In order to do that,
### we would have to have a method to define a prefix length for IPv6, which
### we don't (a NET-* AAAA always defines a /64).
sub _register_address_blocks($$$$@);
sub _register_address_blocks($$$$@) {
  my ($self, $prefix_upper, $ttl, $domain, @nodes) = @_;
  foreach my $node (@nodes) {
    my $fqdn = _fqdn($node->getAttribute('name'), $domain);
    my $type = $node->nodeName();
    my $plen = $node->getAttribute('plen');
    _verbose($self, "Registering $type $fqdn\n");
    my $prefix = eval { IPAM::Prefix->new($node,
					  $node->getAttribute('prefix'),
					  $fqdn, $type eq 'net' ? 1 : 0) }
      or _die_at_node($node, $@);
    $prefix->description($node->findvalue('description'));

    ## Stub nets have an implicit "plen" of the maximum value of
    ## the address family.
    $type eq 'net' and $plen = $af_info{$prefix->af()}{max_plen};
    $prefix->plen($plen);
    eval { $prefix_upper->add($prefix) } or
      _die_at_node($node, $@);
    if ($type eq 'net') {
      if ($prefix->af() == 4) {
	eval { $self->{zone_r}->add_rr($node, $fqdn, $ttl, 'PTR',
				       $prefix->ip()->addr().'.',
				       undef, 1) } or
					 _die_at_node($node, $@);
	eval { $self->{zone_r}->add_rr($node, $fqdn, $ttl, 'A',
				       $prefix->ip()->mask(), undef, 1) } or
					 _die_at_node($node, $@);
      } else {
	eval { $self->{zone_r}->add_rr($node, $fqdn, $ttl, 'AAAA',
				       $prefix->ip()->addr(), undef, 1) } or
					 _die_at_node($node, $@);
      }
    }
    _register_address_blocks($self, $prefix, $ttl, $domain,
			     $node->findnodes('block|net'));
  }
}

### Register address map
sub _register_address_map($$$$) {
  my ($self, $ttl, $domain, $map_node) = @_;
  _verbose($self, "Registering address map\n");
  my $map = IPAM::AddressMap->new($map_node, 'Address Map');
  $self->{address_map} = $map;
  _register_address_blocks($self, $map->registry(), $ttl,
			   $domain, $map_node->findnodes('block|net'));
}

### Traverse a list of element nodes of type "iid" and populate the
### IID registry with IPAM::IID objects named by the fqdn of the host.
sub _register_iids($$@) {
  my ($self, $domain, @nodes) = @_;
  for my $node (@nodes) {
    my $id = $node->getAttribute('id');
    my $use = $node->getAttribute('use');
    if (defined $use and $use eq 'false') {
      $use = 0;
    } else {
      $use = 1;
    }
    my $fqdn = _fqdn($node->getAttribute('name'), $domain);
    my $iid = eval { IPAM::IID->new($node, $fqdn, $id) } or
      _die_at_node($node, $@);
    eval { $self->{iid_r}->add($iid) } or _die_at_node($node, $@);
    $iid->use($use);
    _verbose($self, "Registered IID $id for host $fqdn\n");
  }
}

=item address_map()

my $map = $ipam->address_map();

Returns the L<IPAM::AddressMap> object of the IPAM database.

=cut

### Return the address map.
sub address_map($) {
  my ($self) = @_;
  return($self->{address_map});
}

=item registry($reg)

my $r = $ipam->registry($reg);

Returns the registry object associated with the identifier $reg, which can be one of

IPAM::REG_IID
IPAM::REG_ZONE
IPAM::REG_NETWORK

=cut

### Return the IPAM::Registry objects for one of the registries defined
### by the IPAM::REG_* constants.
sub registry($$) {
  my ($self, $registry) = @_;
  exists $registries{$registry} or return(undef);
  return($self->{$registries{$registry}{key}});
}

=item nameinfo($fqdn)

my $info = $ipam->nameinfo($fqdn);

Returns a reference to a hash with the following keys

=over 4

=item zone

L<IPAM::Zone> object whose name exactly matches $fqdn.

=item iid

L<IPAM::IID> object whose name exactly matches $fqdn.

=item network

List of L<IPAM::Network> objects whose names exactly match $fqdn.

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
  $info{alias} = $self->{network_r}->find_alias($fqdn);
  return(\%info);
}

1;
