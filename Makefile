# -*- mode: makefile -*-
#
# Copyright (c) 2012, Joyent, Inc. All rights reserved.
#

#
# Files
#
DOC_FILES = index.restdown


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

.PHONY: all coal usb boot tar upgrade sandwich


#
# Includes
#

include ./buildtools/mk/Makefile.deps
include ./buildtools/mk/Makefile.targ
