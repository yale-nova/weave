# Copyright (C) 2024
# SPDX-License-Identifier: BSD-3-Clause

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.DEFAULT_GOAL := all

JARS_DIR := fork-jars

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

.PHONY: run
run: all
	@echo "🧪 Running ForkTestSuite natively (no Gramine wrapper yet)..."
	@java -cp $(JARS_DIR)/ForkTestSuite.jar ForkTestSuite 1 32

.PHONY: run-gramine
run-gramine: all
	@echo "🧪 Running ForkTestSuite under Gramine..."
	@gramine-direct bash -c "java -cp $(JARS_DIR)/ForkTestSuite.jar ForkTestSuite 1 32"

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

