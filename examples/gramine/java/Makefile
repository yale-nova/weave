# Copyright (C) 2024 Gramine contributors
# SPDX-License-Identifier: BSD-3-Clause

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)
SRC_DIR := tests
CLASS_DIR := build
JAR_DIR := jars
SRC_FILES := $(wildcard $(SRC_DIR)/*.java)
CLASS_FILES := $(patsubst $(SRC_DIR)/%.java,$(CLASS_DIR)/%.class,$(SRC_FILES))
JAR_FILES := $(patsubst $(SRC_DIR)/%.java,$(JAR_DIR)/%.jar,$(SRC_FILES))

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.DEFAULT_GOAL := all

.PHONY: all
all: deps dirs $(JAR_FILES) java.manifest
ifeq ($(SGX),1)
all: java.manifest.sgx java.sig
endif

.PHONY: dirs
dirs:
	mkdir -p $(CLASS_DIR) $(JAR_DIR) test-outputs test-logs output-data

$(CLASS_DIR)/%.class: $(SRC_DIR)/%.java
	javac -d $(CLASS_DIR) $<

$(JAR_DIR)/%.jar: $(CLASS_DIR)/%.class
	jar cfe $@ $(basename $(notdir $<)) -C $(CLASS_DIR) .

java.manifest: java.manifest.template
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint=$(realpath $(shell sh -c "command -v java")) \
		$< >$@

java.manifest.sgx java.sig: sgx_sign
	@:

.INTERMEDIATE: sgx_sign
sgx_sign: java.manifest
	gramine-sgx-sign \
		--manifest $< \
		--output $<.sgx

.PHONY: check
check: clean all
	./run-java-tests.sh

.PHONY: deps
deps:
	@echo "🔍 Checking and installing required system packages..."
	@DEPS_FILE=system-deps.txt; \
	if [ -f "$$DEPS_FILE" ]; then \
		for pkg in $$(grep -v '^\s*#' $$DEPS_FILE | xargs); do \
			if ! dpkg -s $$pkg >/dev/null 2>&1; then \
				if $(is_in_container); then \
					echo "📦 Installing $$pkg inside container..."; \
					apt-get update && apt-get install -y --no-install-recommends $$pkg; \
				else \
					echo "❌ Missing system package '$$pkg'. Please install manually."; \
					exit 1; \
				fi \
			else \
				echo "✅ $$pkg already installed."; \
			fi; \
		done \
	else \
		echo "⚠️  No system-deps.txt found. Skipping system package installation."; \
	fi

.PHONY: clean
clean:
	$(RM) *.token *.sig *.manifest.sgx *.manifest
	$(RM) -r $(CLASS_DIR) $(JAR_DIR)

.PHONY: distclean
distclean: clean

is_in_container = \
	grep -qE '/docker|/lxc|/kubepods' /proc/1/cgroup 2>/dev/null || \
	[ -f /.dockerenv ] || \
	[ "$$WEAVE_IN_CONTAINER" = "1" ]

