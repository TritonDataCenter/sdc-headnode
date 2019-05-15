# -*- mode: makefile -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
#

PERCENT := %

#
# The headnode build has the following variants, declared by the
# $(HEADNODE_VARIANT) macro:
# 'debug'           use a debug platform image
# 'joyent'          include specific firmware for Joyent deployments
# 'joyent-debug'    a combination of the above
#
ifdef HEADNODE_VARIANT
    HEADNODE_VARIANT_SUFFIX=-$(HEADNODE_VARIANT)
endif

NAME = headnode$(HEADNODE_VARIANT_SUFFIX)

ifeq ($(HEADNODE_VARIANT), debug)
    DEBUG_BUILD=true
endif

ifeq ($(HEADNODE_VARIANT), joyent)
    JOYENT_BUILD=true
    # this is an internal build.
    ENGBLD_DEST_OUT_PATH ?= /stor/builds
endif

ifeq ($(HEADNODE_VARIANT), joyent-debug)
    JOYENT_BUILD=true
    DEBUG_BUILD=true
    # this is an internal build.
    ENGBLD_DEST_OUT_PATH ?= /stor/builds
endif

ifdef DEBUG_BUILD
    DEBUG_SUFFIX=-debug
endif

#
# Files
#

ifeq ($(shell uname -s),SunOS)
GREP = /usr/xpg4/bin/grep
TAR = gtar
TAR_COMPRESSION_ARG = -I pigz
else
GREP = grep
TAR = tar
TAR_COMPRESSION_ARG = -z
endif

BASH_FILES := \
	$(shell find scripts -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find tools/bin tools/lib -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find buildtools/lib -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find bin -exec sh -c "file {} | $(GREP) -q -E '(bash)|(Bourne)'" \; -print)

JS_FILES := \
	$(shell find scripts -exec sh -c "file {} | $(GREP) -q 'node script'" \; -print) \
	$(shell find tools/cmd tools/lib -name '*.js') \
	$(shell find tools/bin -exec sh -c "file {} | $(GREP) -q 'node script'" \; -print | grep -v '/json$$')

JSL_FILES_NODE = $(JS_FILES)
JSSTYLE_FILES = $(JS_FILES)

JSL_CONF_NODE = buildtools/jsl.node.conf
JSSTYLE_FLAGS = -o indent=4,doxygen,unparenthesized-return=0
BASHSTYLE := buildtools/bashstyle

DOWNLOADER := ./bin/downloader
CHECKER := ./bin/checker

EXTRA_CHECK_TARGETS := check-novus

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
	sdc-events \
	sdc-fwapi \
	sdc-imgadm \
	sdc-imgapi \
	sdc-mahi \
	sdc-migrate \
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
	updates-imgadm \
	sdc-volapi

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
	json \
	libdc.sh \
	sdc \
	sdc-amonrelay \
	sdc-backup \
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
	sdc-usbkey \
	sdc-vm \
	sdc-vmmanifest \
	sdc-vmname \
	zoneboot.d

TOOLS_CMD_FILES = \
	sdc-usbkey.js

TOOLS_LIB_FILES = \
	common.js \
	oscmds.js \
	usbkey.js \
	wrap.sh

TOOLS_SHARE_FILES = \
	servicebundle/pubkey.key \
	usbkey

TOOLS_RONN_FILES = \
	man1/sdc-amonrelay.1.ronn \
	man1/sdc-ldap.1.ronn \
	man1/sdc-phonehome.1.ronn \
	man1/sdc-sbcreate.1.ronn \
	man1/sdc-sbupload.1.ronn \
	man1/sdc-ufds-m2s.1.ronn \
	man1/sdc.1.ronn

TOOLS_ETC_FILES= \
	gz-tools.image

TOOLS_UUID = $(shell uuid -v4)

#
# We lay out the contents of /opt/smartdc in the proto/ directory.
#
PROTO =	$(TOP)/proto

PROTO_BIN_FILES = \
	$(TOOLS_BIN_FILES:%=$(PROTO)/opt/smartdc/bin/%) \
	$(SDC_ZONE_BIN_LINKS)

PROTO_CMD_FILES = \
	$(TOOLS_CMD_FILES:%=$(PROTO)/opt/smartdc/cmd/%)

PROTO_LIB_FILES = \
	$(TOOLS_LIB_FILES:%=$(PROTO)/opt/smartdc/lib/%)

PROTO_SHARE_FILES = \
	$(TOOLS_SHARE_FILES:%=$(PROTO)/opt/smartdc/share/%)

PROTO_MAN_FILES = \
	$(TOOLS_RONN_FILES:%.ronn=$(PROTO)/opt/smartdc/man/%) \
	$(SDC_ZONE_MAN_LINKS)

PROTO_ETC_FILES = \
	$(TOOLS_ETC_FILES:%=$(PROTO)/opt/smartdc/etc/%)

ALL_PROTO_FILES = \
	$(PROTO_BIN_FILES) \
	$(PROTO_CMD_FILES) \
	$(PROTO_LIB_FILES) \
	$(PROTO_SHARE_FILES) \
	$(PROTO_MAN_FILES) \
	$(PROTO_ETC_FILES)

#
# This subset of files from the proto/ area is included in the
# cn_tools.tar.gz package for deployment onto Compute Nodes
#
CN_TOOLS_FILES = \
	bin/sdc-sbcreate \
	bin/sdc-usbkey \
	cmd/sdc-usbkey.js \
	lib/common.js \
	lib/oscmds.js \
	lib/usbkey.js \
	man/man1/sdc-sbcreate.1 \
	share/usbkey \
	node_modules \
	etc

TOOLS_DEPS = \
	tools.tar.gz \
	cn_tools.tar.gz

#
# Included definitions
#
ENGBLD_REQUIRE          := $(shell git submodule update --init deps/eng)
include ./deps/eng/tools/mk/Makefile.defs
TOP ?= $(error Unable to access eng.git submodule Makefiles.)

#
# usb-headnode-specific targets
#

.PHONY: all
all: coal gz-tools

check:: $(ESLINT_TARGET) check-jsl check-json $(JSSTYLE_TARGET) check-bash \
    $(EXTRA_CHECK_TARGETS)

0-npm-stamp: package.json
	npm install
	touch $@

#
# Empty rules for these files so that even if they don't exist, we're
# still able to make build.spec.merged.
#
configure-branches build.spec.local:

#
# Primarily a convenience for developers, we convert a simple
# 'configure-branches' file into a 'build.spec.branches' file if a
# configure-branches file is present. This allows developers to declare which
# branches should be used for the build without having to write JSON manually.
#
# The format of configure-branches (also used by the platform build) is:
#
# <key> <colon> <value>
# <hash comment> [any text]
#
build.spec.branches: configure-branches build.spec
	if [ -f configure-branches ]; then \
	    ./bin/convert-configure-branches.js \
	        -c configure-branches -f build.spec -w build.spec.branches; \
	    cat build.spec.branches; \
	fi

build.spec.merged: build.spec build.spec.local build.spec.branches
	rm -f $@
	bin/json-merge $@ $^

#
# Delete any failed image files that might be sitting around before building.
# This is safe because only one headnode build runs at a time. Also cleanup any
# unused lofi devices (used ones will just fail) We look for the string
# 'sdc-headnode-tmp', set by ./bin/build-*-image
#
.PHONY: clean-img-cruft
clean-img-cruft:
ifeq ($(shell uname -s),SunOS)
	for dev in $(shell lofiadm | grep sdc-headnode-tmp | cut -d ' ' -f1 | \
	        grep -v "^Block"); do  \
	    mount | grep "on $${dev}" | cut -d' ' -f1 | while read mntpath; do \
	        pfexec umount $${mntpath}; \
	        done; \
	    pfexec lofiadm -d $${dev}; \
	done
	pfexec rm -rf /tmp/sdc-headnode-tmp.*
endif

CLEAN_FILES += 0-npm-stamp

.PHONY: deps
deps: 0-npm-stamp clean-img-cruft build.spec.merged

.PHONY: coal
coal: deps download $(TOOLS_DEPS)
	TIMESTAMP=$(TIMESTAMP) \
	DEBUG_BUILD=$(DEBUG_BUILD) \
	JOYENT_BUILD=$(JOYENT_BUILD) bin/build-image coal

.PHONY: usb
usb: deps download $(TOOLS_DEPS)
	TIMESTAMP=$(TIMESTAMP) \
	DEBUG_BUILD=$(DEBUG_BUILD) \
	JOYENT_BUILD=$(JOYENT_BUILD) bin/build-image usb

.PHONY: boot
boot: deps download $(TOOLS_DEPS)
	TIMESTAMP=$(TIMESTAMP) \
	DEBUG_BUILD=$(DEBUG_BUILD) \
	JOYENT_BUILD=$(JOYENT_BUILD) bin/build-image tar

.PHONY: tar
tar: boot

.PHONY: sandwich
sandwich:
	@open http://xkcd.com/149/

.PHONY: download
download: deps
	mkdir -p cache
	mkdir -p log
	$(CHECKER)
	if [ -z $${NO_DOWNLOAD} ]; then \
		DEBUG_BUILD=$(DEBUG_BUILD) \
		JOYENT_BUILD=$(JOYENT_BUILD) \
		    $(DOWNLOADER) -d -w "log/artefacts.json"; \
	else \
		true; \
	fi

.PHONY: check-novus
check-novus: deps
	cd buildtools/novus && $(MAKE) check

.PHONY: coal-and-open
coal-and-open: coal
	open $(shell $(GREP) Creating $(shell ls -1t log/build.log.coal.* | head -1) | cut -d' ' -f3 | cut -d/ -f1)*.vmwarevm

.PHONY: update-tools-modules
update-tools-modules:
	./bin/mk-sdc-clients-light.sh v11.3.1 tools/node_modules/sdc-clients

#
# Unlike the rest of the headnode artifacts, $(STAMP) here really does reflect
# the contents of the gz-tools bits. Elsewhere, we use ${PUB_STAMP} to take
# account of any build.spec.local changes
#
GZ_TOOLS_STAMP := gz-tools-$(STAMP)
GZ_TOOLS_MANIFEST := $(GZ_TOOLS_STAMP).manifest
GZ_TOOLS_TARBALL := $(GZ_TOOLS_STAMP).tgz

# NOTE: gz-tools package version comes from package.json
.PHONY: gz-tools
gz-tools: $(TOOLS_DEPS)
	@echo "building $(GZ_TOOLS_TARBALL)"
	mkdir -p build/$(GZ_TOOLS_STAMP)
	cp -r $(TOP)/scripts build/$(GZ_TOOLS_STAMP)/gz-tools
	cp -r \
		$(TOP)/tools.tar.gz \
		$(TOP)/cn_tools.tar.gz \
		$(TOP)/default \
		$(TOP)/scripts \
		build/$(GZ_TOOLS_STAMP)/gz-tools
	(cd build/$(GZ_TOOLS_STAMP) && $(TAR) $(TAR_COMPRESSION_ARG) -cf ../../$(GZ_TOOLS_TARBALL) gz-tools)
	cat $(PROTO)/opt/smartdc/etc/gz-tools.image > build/$(GZ_TOOLS_STAMP)/image_uuid
	cat $(TOP)/manifests/gz-tools.manifest.tmpl | sed \
		-e "s/UUID/$$(cat build/$(GZ_TOOLS_STAMP)/image_uuid)/" \
		-e "s/NAME/gz-tools/" \
		-e "s/VERSION/$$(json version < $(TOP)/package.json)/" \
		-e "s/SIZE/$$(stat --printf="%s" $(GZ_TOOLS_TARBALL))/" \
		-e "s/BUILDSTAMP/$(STAMP)/" \
		-e "s/SHA/$$(openssl sha1 $(GZ_TOOLS_TARBALL) \
		    | cut -d ' ' -f2)/" \
		> $(TOP)/$(GZ_TOOLS_MANIFEST)
	rm -rf build/$(GZ_TOOLS_STAMP)

CLEAN_FILES += build/gz-tools *.tgz \
	$(GZ_TOOLS_MANIFEST) \
	release.json \
	build.spec.branches \
	build.spec.merged

#
# Tools tarball
#

tools.tar.gz: tools
	rm -f $(TOP)/tools.tar.gz
	cd $(PROTO)/opt/smartdc && $(TAR) $(TAR_COMPRESSION_ARG) -cf $(TOP)/$(@F) \
	    bin cmd share lib man node_modules etc

#
# Compute Node Tools subset tarball
#

cn_tools.tar.gz: tools
	rm -f $(TOP)/cn_tools.tar.gz
	cd $(PROTO)/opt/smartdc && $(TAR) $(TAR_COMPRESSION_ARG) -cf $(TOP)/$(@F) \
	    $(CN_TOOLS_FILES)

#
# Tools
#

.PHONY: tools
tools: man $(ALL_PROTO_FILES)
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

$(PROTO)/opt/smartdc/cmd/%: tools/cmd/%
	mkdir -p $(@D)
	rm -f $@
	cp $^ $@
	chmod 755 $@
	touch $@

$(PROTO)/opt/smartdc/etc/gz-tools.image:
	mkdir -p $(@D)
	rm -f $@
	echo $(TOOLS_UUID) > $@
	chmod 644 $@

USBKEY_SCRIPTS = \
	scripts/update-usbkey.0.esp.sh \
	scripts/update-usbkey.5.copy-contents.js

USBKEY_TARBALLS = \
	cache/file.ipxe.tar.gz \
	cache/file.platboot$(DEBUG_SUFFIX).tgz

$(USBKEY_TARBALLS): download

#
# The usbkey sub-directory, included in the tarballs, represents new contents
# that should be updated on USB keys, in particular any updates of loader or
# iPXE.
#
$(PROTO)/opt/smartdc/share/usbkey: $(USBKEY_SCRIPTS) $(USBKEY_TARBALLS)
	mkdir -p $@/contents
	cp -f $(USBKEY_SCRIPTS) $@/
	for tar in $(USBKEY_TARBALLS); do \
		$(TAR) -C $@/contents -xvf $$tar || exit 1; \
	done
	cp -fr boot $@/contents
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
	$(TOP)/buildtools/ronnjs/bin/ronn.js \
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
# Artifact publication, typically used for Jenkins builds. We compute
# PUB_STAMP and BRANCH_STAMP in the target rather than as a Makefile macro
# since its value depends on us possibly generating a build.spec.branches file
# first.
#
.PHONY: release-json
release-json: build.spec.merged
	UNIQUE_BRANCHES=$$(./bin/unique-branches $(BRANCH)); \
	PUB_STAMP=$(BRANCH)$$UNIQUE_BRANCHES-$(TIMESTAMP)-$(_GITDESCRIBE); \
	BRANCH_STAMP=$(BRANCH)$$UNIQUE_BRANCHES; \
	BUILD_TGZ=$$(./bin/buildspec build-tgz); \
	if [[ "$$BUILD_TGZ" == true ]]; then \
	    echo "{ \
	        \"date\": \"$(TIMESTAMP)\", \
	       \"branch\": \"$$BRANCH_STAMP\", \
	       \"coal\": \"coal$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP-4g.tgz\", \
	       \"boot\": \"boot$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP.tgz\", \
	       \"usb\": \"usb$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP.tgz\" \
	    }" | json > release.json; \
	else \
	    echo "{ \
	        \"date\": \"$(TIMESTAMP)\", \
	        \"branch\": \"$$BRANCH_STAMP\", \
	        \"coal\": \"coal$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP-4g.tgz\" \
	    }" | json > release.json; \
	fi

#
# This publish target rewrites 'latest-build-stamp' overriding what
# Makefile.targ does in its 'prepublish' target. This is here so that we can
# invoke 'bits-upload-latest', and get a Manta directory path that includes
# the timestamp annotated with the output from 'unique-branches'. This serves
# to disambiguate headnode builds that were assembled from different sets
# of component images.
#
# Note that if doing a build-tgz=false build, where the boot and usb
# directories gets renamed or removed during the build, we intentionally only
# upload the coal artifact. As bits-upload will only upload files, not
# directories, we create an uncompressed tar archive of that.
#
.PHONY: publish
publish: release-json
	mkdir -p $(ENGBLD_BITS_DIR)/$(NAME)
	mv $(GZ_TOOLS_MANIFEST) $(ENGBLD_BITS_DIR)/$(NAME)
	mv $(GZ_TOOLS_TARBALL) $(ENGBLD_BITS_DIR)/$(NAME)
	UNIQUE_BRANCHES=$$(./bin/unique-branches $(BRANCH)); \
	PUB_STAMP=$(BRANCH)$$UNIQUE_BRANCHES-$(TIMESTAMP)-$(_GITDESCRIBE); \
	BRANCH_STAMP=$(BRANCH)$$UNIQUE_BRANCHES; \
	BUILD_TGZ=$$(./bin/buildspec build-tgz); \
	if [[ "$$BUILD_TGZ" == true ]]; then \
	    mv coal-$(STAMP)-4gb.tgz \
	        $(ENGBLD_BITS_DIR)/$(NAME)/coal$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP-4gb.tgz && \
	    mv boot-$(STAMP).tgz \
	        $(ENGBLD_BITS_DIR)/$(NAME)/boot$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP.tgz && \
	    mv usb-$(STAMP).tgz \
	        $(ENGBLD_BITS_DIR)/$(NAME)/usb$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP.tgz; \
	else \
	    echo "build-tgz was false: uploading only compressed coal artifact" && \
	    $(TAR) $(TAR_COMPRESSION_ARG) -cf \
	        $(ENGBLD_BITS_DIR)/$(NAME)/coal$(HEADNODE_VARIANT_SUFFIX)-$$PUB_STAMP-4gb.tgz \
	        coal-$(STAMP)-4gb.vmwarevm; \
	fi && \
	echo "$$PUB_STAMP" > \
	    $(ENGBLD_BITS_DIR)/$(NAME)/latest-build-stamp
	json < build.spec.merged > $(ENGBLD_BITS_DIR)/$(NAME)/build.spec.merged
	cp release.json $(ENGBLD_BITS_DIR)/$(NAME)

ENGBLD_BITS_UPLOAD_OVERRIDE=true

#
# We override bits-upload and bits-upload latest so that we can pass extended
# branch information via $PUB_STAMP and $BRANCH_STAMP, which we need to compute
# in the target rather than a Makefile macro, as that information gets
# generated by the 'build-spec-local' target.
#
.PHONY: bits-upload
bits-upload: publish
	UNIQUE_BRANCHES=$$(./bin/unique-branches $(BRANCH)); \
	PUB_STAMP=$(BRANCH)$$UNIQUE_BRANCHES-$(TIMESTAMP)-$(_GITDESCRIBE); \
	BRANCH_STAMP=$(BRANCH)$$UNIQUE_BRANCHES; \
	$(TOP)/deps/eng/tools/bits-upload.sh \
	    -b $$BRANCH_STAMP \
	    $(BITS_UPLOAD_LOCAL_ARG) \
	    $(BITS_UPLOAD_IMGAPI_ARG) \
	    -d $(ENGBLD_DEST_OUT_PATH)/$(NAME) \
	    -D $(ENGBLD_BITS_DIR) \
	    -n $(NAME) \
	    -t $$PUB_STAMP

.PHONY: bits-upload-latest
bits-upload-latest: build.spec.merged
	BRANCH_STAMP=$(BRANCH)$$(./bin/unique-branches $(BRANCH)); \
	$(TOP)/deps/eng/tools/bits-upload.sh \
	    -b $$BRANCH_STAMP \
	    $(BITS_UPLOAD_LOCAL_ARG) \
	    $(BITS_UPLOAD_IMGAPI_ARG) \
	    -d $(ENGBLD_DEST_OUT_PATH)/$(NAME) \
	    -D $(ENGBLD_BITS_DIR) \
	    -n $(NAME)

#
# Includes
#

include ./deps/eng/tools/mk/Makefile.deps
include ./deps/eng/tools/mk/Makefile.targ

