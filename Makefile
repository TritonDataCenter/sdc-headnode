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
