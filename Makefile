# -*- mode: makefile -*-
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#

#
# Files
#
DOC_FILES = index.restdown

BASH_FILES = \
	$(shell find scripts -exec sh -c "file {} | grep -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find tools -exec sh -c "file {} | grep -q -E '(bash)|(Bourne)'" \; -print) \
	$(shell find bin -exec sh -c "file {} | grep -q -E '(bash)|(Bourne)'" \; -print)

JS_FILES = \
	$(shell find scripts -exec sh -c "file {} | grep -q 'node script'" \; -print) \
	$(shell find tools -exec sh -c "file {} | grep -q 'node script'" \; -print)

JSL_FILES_NODE = $(JS_FILES)
JSSTYLE_FILES = $(JS_FILES)

JSL_CONF_NODE = buildtools/jsl.node.conf
JSSTYLE_FLAGS = -o indent=4,doxygen,unparenthesized-return=0


#
# Included definitions
#
include ./buildtools/mk/Makefile.defs


#
# usb-headnode-specific targets
#

.PHONY: all coal deps usb boot tar upgrade sandwich
all: coal

deps:
	npm install

coal: deps
	bin/build-image coal

usb: deps
	bin/build-image usb

boot: deps
	bin/build-image tar

tar: boot
upgrade:
	bin/build-upgrade-image $(shell ls boot-*.tgz | sort | tail -1)

sandwich:
	@open http://xkcd.com/149/

.PHONY: coal-and-open
coal-and-open: coal
	open $(shell grep Creating $(shell ls -1t log/build.log.coal.* | head -1) | cut -d' ' -f3 | cut -d/ -f1)*.vmwarevm

.PHONY: update-tools-modules
update-tools-modules:
	./bin/mk-sdc-clients-light.sh da0a1080feb tools-modules/sdc-clients

.PHONY: incr-upgrade
incr-upgrade:
	@echo building incr-upgrade-$(STAMP).tgz
	rm -rf build/incr-upgrade
	mkdir -p build
	cp -r $(TOP)/incr-upgrade-scripts build/incr-upgrade-$(STAMP)
	cp -r \
		$(TOP)/zones \
		$(TOP)/tools \
		$(TOP)/default \
		$(TOP)/scripts \
		build/incr-upgrade-$(STAMP)
	(cd build && tar czf ../incr-upgrade-$(STAMP).tgz incr-upgrade-$(STAMP))

CLEAN_FILES += build/incr-upgrade




#
# Includes
#

include ./buildtools/mk/Makefile.deps
include ./buildtools/mk/Makefile.targ
