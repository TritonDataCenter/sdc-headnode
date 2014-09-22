# -*- mode: makefile -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

PERCENT := %

#
# Files
#

ifeq ($(shell uname -s),Darwin)
GREP = grep
else
GREP = /usr/xpg4/bin/grep
endif

BASH_FILES = \
	$(shell find scripts -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find tools -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find bin -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print)

JS_FILES = \
	$(shell find scripts -exec sh -c "file {} | $(GREP) -q 'node script'" \; -print) \
	$(shell find tools/bin -exec sh -c "file {} | $(GREP) -q 'node script'" \; -print)

JSL_FILES_NODE = $(JS_FILES)
JSSTYLE_FILES = $(JS_FILES)

JSL_CONF_NODE = buildtools/jsl.node.conf
JSSTYLE_FLAGS = -o indent=4,doxygen,unparenthesized-return=0
BASHSTYLE := buildtools/bashstyle

#
# These commands are delivered as part of the "sdc" zone image.  We ship
# a small shell-script wrapper in the global zone (tools/lib/wrap.sh)
# and symlink the following command names to it.  We also use this list
# to create dangling symlinks to manual pages.
#
SDC_ZONE_COMMANDS = \
	amqpsnoop \
	sdc-amon \
	sdc-amonadm \
	sdc-cnapi \
	sdc-dapi \
	sdc-fwapi \
	sdc-imgadm \
	sdc-imgapi \
	sdc-napi \
	sdc-oneachnode \
	sdc-papi \
	sdc-req \
	sdc-sapi \
	sdc-ufds \
	sdc-useradm \
	sdc-vmadm \
	sdc-vmapi \
	sdc-waitforjob \
	sdc-workflow \
	updates-imgadm

SDC_ZONE_MAN_LINKS = \
	$(SDC_ZONE_COMMANDS:%=$(PROTO)/opt/smartdc/man/man1/%.1)

SDC_ZONE_BIN_LINKS = \
	$(SDC_ZONE_COMMANDS:%=$(PROTO)/opt/smartdc/bin/%)

#
# These source files in tools/ are shipped in tools.tar.gz to be deployed in
# /opt/smartdc.
#
TOOLS_BIN_FILES = \
	joyent-imgadm \
	libdc.sh \
	sdc \
	sdc-amonrelay \
	sdc-backup \
	sdc-create-2nd-manatee \
	sdc-healthcheck \
	sdc-heartbeatsnoop \
	sdc-image-sync \
	sdc-ldap \
	sdc-login \
	sdc-network \
	sdc-phonehome \
	sdc-rabbitstat \
	sdc-restore \
	sdc-role \
	sdc-sbcreate \
	sdc-sbupload \
	sdc-server \
	sdc-setconsole \
	sdc-ufds-m2s \
	sdc-vm \
	sdc-vmmanifest \
	sdc-vmname \
	zoneboot.d

TOOLS_LIB_FILES = \
	wrap.sh

TOOLS_SHARE_FILES = \
	servicebundle/pubkey.key

TOOLS_RONN_FILES = \
	man1/sdc-amonrelay.1.ronn \
	man1/sdc-ldap.1.ronn \
	man1/sdc-sbcreate.1.ronn \
	man1/sdc-sbupload.1.ronn \
	man1/sdc-ufds-m2s.1.ronn \
	man1/sdc.1.ronn

#
# We lay out the contents of /opt/smartdc in the proto/ directory.
#
PROTO =	$(TOP)/proto

PROTO_BIN_FILES = \
	$(TOOLS_BIN_FILES:%=$(PROTO)/opt/smartdc/bin/%) \
	$(SDC_ZONE_BIN_LINKS)

PROTO_LIB_FILES = \
	$(TOOLS_LIB_FILES:%=$(PROTO)/opt/smartdc/lib/%)

PROTO_SHARE_FILES = \
	$(TOOLS_SHARE_FILES:%=$(PROTO)/opt/smartdc/share/%)

PROTO_MAN_FILES = \
	$(TOOLS_RONN_FILES:%.ronn=$(PROTO)/opt/smartdc/man/%) \
	$(SDC_ZONE_MAN_LINKS)

#
# This subset of files from the proto/ area is included in the
# cn_tools.tar.gz package for deployment onto Compute Nodes
#
CN_TOOLS_FILES = \
	bin/sdc-sbcreate \
	man/man1/sdc-sbcreate.1

TOOLS_DEPS = \
	tools.tar.gz \
	cn_tools.tar.gz

#
# Included definitions
#
include ./buildtools/mk/Makefile.defs


#
# usb-headnode-specific targets
#

.PHONY: all coal deps usb boot tar sandwich
all: coal

deps:
	npm install

coal: deps $(TOOLS_DEPS)
	bin/build-image coal

usb: deps $(TOOLS_DEPS)
	bin/build-image usb

boot: deps $(TOOLS_DEPS)
	bin/build-image tar

tar: boot

sandwich:
	@open http://xkcd.com/149/

.PHONY: coal-and-open
coal-and-open: coal
	open $(shell $(GREP) Creating $(shell ls -1t log/build.log.coal.* | head -1) | cut -d' ' -f3 | cut -d/ -f1)*.vmwarevm

.PHONY: update-tools-modules
update-tools-modules:
	./bin/mk-sdc-clients-light.sh 8ff6bc5 tools/node_modules/sdc-clients

.PHONY: incr-upgrade
incr-upgrade: $(TOOLS_DEPS)
	@echo building incr-upgrade-$(STAMP).tgz
	rm -rf build/incr-upgrade
	mkdir -p build
	cp -r $(TOP)/incr-upgrade-scripts build/incr-upgrade-$(STAMP)
	cp -r \
		$(TOP)/zones \
		$(TOP)/tools.tar.gz \
		$(TOP)/cn_tools.tar.gz \
		$(TOP)/default \
		$(TOP)/scripts \
		build/incr-upgrade-$(STAMP)
	(cd build && tar czf ../incr-upgrade-$(STAMP).tgz incr-upgrade-$(STAMP))

CLEAN_FILES += build/incr-upgrade


GZ_TOOLS_STAMP := gz-tools-$(STAMP)
GZ_TOOLS_MANIFEST := $(GZ_TOOLS_STAMP).manifest
GZ_TOOLS_TARBALL := $(GZ_TOOLS_STAMP).tgz

# NOTE: gz-tools package version comes from package.json
.PHONY: gz-tools
gz-tools: $(TOOLS_DEPS)
	@echo "building $(GZ_TOOLS_TARBALL)"
	rm -rf build/gz-tools
	mkdir -p build/gz-tools
	cp -r $(TOP)/scripts build/gz-tools/$(GZ_TOOLS_STAMP)
	cp -r \
		$(TOP)/tools.tar.gz \
		$(TOP)/cn_tools.tar.gz \
		$(TOP)/default \
		$(TOP)/scripts \
		build/gz-tools/$(GZ_TOOLS_STAMP)
	(cd build/gz-tools && tar czf ../../$(GZ_TOOLS_TARBALL) $(GZ_TOOLS_STAMP))
	uuid -v4 > build/gz-tools/image_uuid
	cat $(TOP)/manifests/gz-tools.manifest.tmpl | sed \
		-e "s/UUID/$$(cat build/gz-tools/image_uuid)/" \
		-e "s/NAME/gz-tools/" \
		-e "s/VERSION/$$(json version < $(TOP)/package.json)/" \
		-e "s/SIZE/$$(stat --printf="%s" $(GZ_TOOLS_TARBALL))/" \
		-e "s/BUILDSTAMP/$(STAMP)/" \
		-e "s/SHA/$$(openssl sha1 $(GZ_TOOLS_TARBALL) \
		    | cut -d ' ' -f2)/" \
		> $(TOP)/$(GZ_TOOLS_MANIFEST)

CLEAN_FILES += build/gz-tools

.PHONY: gz-tools-publish
gz-tools-publish: gz-tools
	@if [[ -z "$(BITS_DIR)" ]]; then \
		@echo "error: 'BITS_DIR' must be set for 'gz-tools-publish' target"; \
		exit 1; \
	fi
	mkdir -p $(BITS_DIR)/gz-tools
	cp $(TOP)/$(GZ_TOOLS_TARBALL) $(BITS_DIR)/gz-tools/$(GZ_TOOLS_TARBALL)
	cp $(TOP)/$(GZ_TOOLS_MANIFEST) $(BITS_DIR)/gz-tools/$(GZ_TOOLS_MANIFEST)


#
# Tools tarball
#

tools.tar.gz: tools
	rm -f $(TOP)/tools.tar.gz
	cd $(PROTO)/opt/smartdc && tar cfz $(TOP)/$(@F) \
	    bin share lib man node_modules

#
# Compute Node Tools subset tarball
#

cn_tools.tar.gz: tools
	rm -f $(TOP)/cn_tools.tar.gz
	cd $(PROTO)/opt/smartdc && tar cfz $(TOP)/$(@F) \
	    $(CN_TOOLS_FILES)

#
# Tools
#

.PHONY: tools
tools: man $(PROTO_LIB_FILES) $(PROTO_BIN_FILES) $(PROTO_SHARE_FILES)
	rm -rf $(PROTO)/opt/smartdc/node_modules
	cp -RP tools/node_modules $(PROTO)/opt/smartdc/node_modules

$(PROTO)/opt/smartdc/lib/%: tools/lib/%
	mkdir -p $(@D)
	rm -f $@
	cp $^ $@
	chmod 755 $@
	touch $@

$(PROTO)/opt/smartdc/share/%: tools/share/%
	mkdir -p $(@D)
	rm -f $@
	cp $^ $@
	chmod 444 $@
	touch $@

$(PROTO)/opt/smartdc/bin/%: tools/bin/%
	mkdir -p $(@D)
	rm -f $@
	cp $^ $@
	chmod 755 $@
	touch $@

$(SDC_ZONE_BIN_LINKS):
	mkdir -p $(@D)
	rm -f $@
	ln -s ../lib/wrap.sh $@

CLEAN_FILES += proto tools.tar.gz cn_tools.tar.gz

#
# Tools manual pages
#

.PHONY: man
man: $(PROTO_MAN_FILES)

$(PROTO)/opt/smartdc/man/%: tools/man/%.ronn
	mkdir -p $(@D)
	rm -f $@
	$(TOP)/bin/ronnjs/bin/ronn.js \
	    --roff $^ \
	    --date `git log -1 --date=short --pretty=format:$(PERCENT)cd $^` \
	    `date +$(PERCENT)Y` \
	    > $@
	chmod 444 $@

# We create blank manual pages in $(PROTO)/opt/smartdc/sdc so that make is
# not confused by the dangling symlinks, which cause it to re-run the target
# every build
$(SDC_ZONE_MAN_LINKS):
	mkdir -p $(PROTO)/opt/smartdc/sdc/man/man1
	touch $(PROTO)/opt/smartdc/sdc/man/man1/$(@F)
	mkdir -p $(@D)
	rm -f $@
	ln -s ../../sdc/man/man1/$(@F) $@



#
# Includes
#

include ./buildtools/mk/Makefile.deps
include ./buildtools/mk/Makefile.targ
