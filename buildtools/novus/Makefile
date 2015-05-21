
ROOT =			$(PWD)
NODE_MOD_BIN =		$(ROOT)/../../node_modules/.bin

JSHINT =		$(NODE_MOD_BIN)/jshint
JSCS =			$(NODE_MOD_BIN)/jscs

CHECK_JS_FILES =	$(shell find $(ROOT)/cmd $(ROOT)/lib -name \*.js)

.PHONY: check
check:
	@$(JSHINT) $(CHECK_JS_FILES)
	@$(JSCS) $(CHECK_JS_FILES)

