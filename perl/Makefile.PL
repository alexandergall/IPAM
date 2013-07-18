use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'IPAM',
    VERSION_FROM      => 'lib/IPAM.pm', # finds $VERSION
    PREREQ_PM         => { XML::LibXML => 1.70,
			   NetAddr::IP => 4.028 },
    EXE_FILES         => ['bin/ipam-whatis', 'bin/ipam-free', 
			  'bin/ipam-gen-zones', 'bin/ipam-alternatives',
			  'bin/ipam-check', 'bin/ipam-select',
			  'bin/ipam-router-info', 'bin/ipam-create-cache', 
			  'bin/ipam.cgi', ],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/IPAM.pm', # retrieve abstract from module
       AUTHOR         => 'Alexander Gall <gall@switch.chb>') : ()),
);
