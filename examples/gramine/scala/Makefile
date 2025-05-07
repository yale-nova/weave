# Copyright (C) 2024 Gramine contributors
# SPDX-License-Identifier: BSD-3-Clause

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.DEFAULT_GOAL := all

JARS_DIR := jars

# === Default full build ===
ifeq ($(SGX),1)
all: deps dirs build-jars java.manifest java.manifest.sgx java.sig
else
all: deps dirs build-jars java.manifest
endif

.PHONY: dirs
dirs:
	mkdir -p $(JARS_DIR) test-outputs test-logs output-data

.PHONY: build-jars
build-jars:
	@echo "🔨 Building fat JARs..."
	@./scripts/build-fatjars.sh --no-rebuild

.PHONY: java.manifest
java.manifest: java.manifest.template
	@if [ ! -d "$(JARS_DIR)" ] || [ -z "$$(ls -A $(JARS_DIR))" ]; then \
		echo "⚠️  Warning: No JARs found in $(JARS_DIR) — the manifest may be invalid."; \
	fi
	@echo "📝 Generating Gramine manifest..."
	@gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint=$(realpath $(shell sh -c "command -v java")) \
		$< > $@

.PHONY: java.manifest.sgx java.sig
java.manifest.sgx java.sig: sgx_sign
	@:

.INTERMEDIATE: sgx_sign
sgx_sign: java.manifest
	@echo "🔐 Signing SGX manifest..."
	@gramine-sgx-sign \
		--manifest $< \
		--output $<.sgx

.PHONY: check
check: clean all
	@echo "🔍 Checking for Gramine support..."
	@if command -v gramine-direct >/dev/null 2>&1 && [ -f java.manifest.template ]; then \
		echo "🧪 Gramine found — running under gramine-direct..."; \
		./scripts/run-scala-tests.sh; \
	else \
		echo "🧪 Gramine not available — falling back to native tests..."; \
		./scripts/run-scala-tests.sh --native; \
	fi

.PHONY: run-native
run-native:
	@./scripts/run-scala-tests.sh --native

.PHONY: run-gramine
run-gramine:
	@./scripts/run-scala-tests.sh

.PHONY: validate
validate: clean all run-native run-gramine

.PHONY: deps
deps:
	@echo "🔧 Installing system and build dependencies..."
	@bash scripts/install-build-tools.sh
	@bash scripts/install-system-deps.sh || bash scripts/install-system-deps.sh

.PHONY: clean
clean:
	@echo "🧹 Cleaning Gramine artifacts..."
	$(RM) *.token *.sig *.manifest.sgx *.manifest
	$(RM) -rf test-outputs test-logs output-data

.PHONY: distclean
distclean: clean
	@echo "🔥 Deep cleaning JARs and build cache..."
	$(RM) -rf $(JARS_DIR) target project/target project/project
