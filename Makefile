# -*- mode: makefile -*-
#
# Copyright (c) 2013, Joyent, Inc. All rights reserved.
#

#
# Files
#
DOC_FILES = index.restdown

BASH_FILES = \
    $(shell find scripts -name '*.sh') \
    $(shell find tools -depth -name "*.d" -prune -o -name "\.*" -prune -o \
        -name tools -prune -o -print) \
    bin/upgrade.sh \
    bin/upgrade_hooks.sh \
    scripts/chk_agents \
    scripts/update_agents

JS_FILES = $(shell find scripts -name '*.js')
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

all: coal

coal:
	bin/build-image coal
usb:
	bin/build-image usb
boot:
	bin/build-image tar
tar: boot
upgrade:
	bin/build-upgrade-image $(shell ls boot-*.tgz | sort | tail -1)
sandwich:
	@open http://xkcd.com/149/

coal-and-open: coal
	open $(shell ls -1d coal-*.vmwarevm | sort | tail -1)

.PHONY: all coal usb boot tar upgrade sandwich

.PHONY: update-tools-modules
update-tools-modules:
	./bin/mk-sdc-clients-light.sh da0a1080feb tools-modules/sdc-clients



#
# Includes
#

include ./buildtools/mk/Makefile.deps
include ./buildtools/mk/Makefile.targ
