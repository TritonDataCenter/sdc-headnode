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
tar:
	bin/build-image -c tar
sandwich:
	@open http://xkcd.com/149/

.PHONY: all coal usb tar sandwich


#
# Includes
#

include ./buildtools/mk/Makefile.deps
include ./buildtools/mk/Makefile.targ
