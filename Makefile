ifeq ($(VERSION), "")
	@echo "Use gmake"
endif

all: coal

coal:
	bin/build-image
usb:
	bin/build-image usb
upgrade:
	bin/build-image upgrade
tar:
	bin/build-image tar
sandwich:
	@open http://xkcd.com/149/

.PHONY: all coal usb upgrade tar sandwich
