.PHONY: all clean test

all:
	@echo "🚀 Building weave-artifacts"
	$(MAKE) -C examples/gramine/python all
	$(MAKE) -C examples/gramine/java all
	$(MAKE) -C examples/gramine/scala all

test:
	@echo "🧪 Running tests for weave-artifacts"
	$(MAKE) -C examples/gramine/python check
	$(MAKE) -C examples/gramine/java check
	$(MAKE) -C examples/gramine/scala check

clean:
	@echo "🧹 Cleaning weave-artifacts"
	$(MAKE) -C examples/gramine/python clean
	$(MAKE) -C examples/gramine/java clean
	$(MAKE) -C examples/gramine/scala clean

clean:
	    @echo "🔥 Deep cleaning weave-artifacts"
	    $(MAKE) -C examples/gramine/python distclean
	    $(MAKE) -C examples/gramine/java distclean
	    $(MAKE) -C examples/gramine/scala distclean
