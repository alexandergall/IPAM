PATH = /bin:/usr/bin
SHELL = /bin/bash
INSTALL = install -g bind
INSTALL_DIR = /home/noc/IPAM
DIRS = $(INSTALL_DIR) $(patsubst %,$(INSTALL_DIR)/%,networks schemas zones blocks)
SCHEMAS = $(patsubst %,$(INSTALL_DIR)/%,$(wildcard schemas/*.rnc))
LOCATING_FILES = $(INSTALL_DIR)/schemas.xml $(INSTALL_DIR)/networks/schemas.xml $(INSTALL_DIR)/blocks/schemas.xml
define transform
	sed -e 's%@@IPAM_BASE@@%$(INSTALL_DIR)%' $< > $<.tmp
	$(INSTALL) -m 664 $<.tmp $@
	rm -f $<.tmp
endef

install: $(DIRS) install.perl $(INSTALL_DIR)/Makefile $(SCHEMAS) $(LOCATING_FILES)

$(DIRS):
	$(INSTALL) -m02775 -d $@

install.perl: perl/Makefile
	cd perl && make install

perl/Makefile: perl/Makefile.PL
	cd perl && perl Makefile.PL INSTALL_BASE=$(INSTALL_DIR)

$(INSTALL_DIR)/Makefile: Makefile.in
	$(transform)

$(INSTALL_DIR)/schemas.xml: schemas/schemas.xml.in
	$(transform)

$(INSTALL_DIR)/networks/schemas.xml: schemas/schemas-networks.xml.in
	$(transform)

$(INSTALL_DIR)/blocks/schemas.xml: schemas/schemas-blocks.xml.in
	$(transform)

$(INSTALL_DIR)/%.rnc: %.rnc
	$(INSTALL) -m 444 $< -D $@
