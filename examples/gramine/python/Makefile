# Wrapper Makefile for Python Gramine Project
# SPDX-License-Identifier: BSD-3-Clause

# ----------------------------------------
# Environment & Configuration
# ----------------------------------------

MAKECMDGOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),all)

ifeq ($(MAKECMDGOALS),setup)
# Do nothing to prevent infinite loop
else
$(MAKECMDGOALS): setup
endif

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)
RA_TYPE ?= dcap
PYTHON := python3
POETRY_FALLBACK := $$HOME/.local/share/pypoetry/venv/bin/poetry
POETRY_BIN := $(shell \
	if command -v poetry >/dev/null 2>&1; then \
		command -v poetry; \
	elif [ -x $(POETRY_FALLBACK) ]; then \
		echo $(POETRY_FALLBACK); \
	else \
		echo ""; \
	fi)

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.DEFAULT_GOAL := all

# ----------------------------------------
# Dependency Check Only (no install)
# ----------------------------------------

.PHONY: ensure-poetry
ensure-poetry:
	@if [ -z "$(POETRY_BIN)" ]; then \
		echo "❌ Poetry is not installed or not in PATH. Set ENV PATH correctly or install Poetry."; \
		exit 1; \
	else \
		echo "✅ Poetry found at $(POETRY_BIN)"; \
	fi

.PHONY: setup
setup: ensure-poetry
	@echo "📦 Verifying Python dependencies using Poetry..."

	# Detect container context
	@IS_CONTAINER=$$(grep -qE '/docker|/lxc|/kubepods' /proc/1/cgroup 2>/dev/null && echo 1 || [ -f /.dockerenv ] && echo 1 || [ "$$WEAVE_IN_CONTAINER" = "1" ] && echo 1 || echo 0); \
	if [ "$$IS_CONTAINER" = "1" ]; then \
		echo "🐳 Detected container — disabling Poetry virtualenvs..."; \
		$(POETRY_BIN) config virtualenvs.create false --local; \
	else \
		echo "🛡️  Running outside container — keeping Poetry virtualenv behavior."; \
	fi

	@if [ pyproject.toml -nt poetry.lock ]; then \
		echo "🔄 Detected changes in pyproject.toml, regenerating poetry.lock..."; \
		$(POETRY_BIN) lock; \
	fi


	@echo "🔍 Running poetry dry-run for dependency check..."
	@DRYRUN_OUTPUT="$$( $(POETRY_BIN) install --dry-run --no-root )"; \
	echo "$$DRYRUN_OUTPUT"; \
	echo "$$DRYRUN_OUTPUT" | grep -E '^\s*- Installing [^:]+: (?!Skipped)' || true; \
	MISSING=$$(echo "$$DRYRUN_OUTPUT" | grep -E '^\s*- Installing [^:]+: (?!Skipped)' > /dev/null; echo $$?); \
	if [ "$$MISSING" -eq 0 ]; then \
		echo "❌ Some dependencies would be installed (not already installed or skipped). Please run 'poetry install' manually."; \
		exit 1; \
	else \
		echo "✅ All dependencies are already installed."; \
	fi

.PHONY: update-deps
update-deps: ensure-poetry
	@echo "🔄 Updating Python dependencies using Poetry..."
	@$(POETRY_BIN) lock && $(POETRY_BIN) update

# ----------------------------------------
# Build Targets
# ----------------------------------------

.PHONY: all python.manifest
all: setup python.manifest
ifeq ($(SGX),1)
all: python.manifest.sgx python.sig
endif

python.manifest:
	@echo "🛠️  Generating Gramine manifest..."
	@gramine-manifest \
	-Dlog_level=$(GRAMINE_LOG_LEVEL) \
	-Darch_libdir=$(ARCH_LIBDIR) \
	-Dentrypoint=$(realpath $(shell sh -c "command -v python3")) \
	-Dra_type=$(RA_TYPE) \
	python.manifest.template > python.manifest

python.manifest.sgx python.sig &: python.manifest
	@echo "🔐 Signing SGX manifest..."
	@gramine-sgx-sign \
	--manifest $< \
	--output $<.sgx

# ----------------------------------------
# Test & Clean
# ----------------------------------------

.PHONY: check
check: all
	@echo "✅ Running tests..."
	@./run_tests.sh > TEST_STDOUT 2> TEST_STDERR
	@if grep -q "Success 1/4" TEST_STDOUT; then echo "✅ Test 1/4 (helloworld) passed"; else echo "❌ Test 1/4 (helloworld) failed"; fi
	@if grep -q "Success 2/4" TEST_STDOUT; then echo "✅ Test 2/4 (http server/client) passed"; else echo "❌ Test 2/4 (http server/client) failed"; fi
	@if grep -q "Success 3/4" TEST_STDOUT; then echo "✅ Test 3/4 (numpy) passed"; else echo "❌ Test 3/4 (numpy) failed"; fi
	@if grep -q "Success 4/4" TEST_STDOUT; then echo "✅ Test 4/4 (scipy) passed"; else echo "❌ Test 4/4 (scipy) failed"; fi
ifeq ($(SGX),1)
	@if grep -q "Success SGX report" TEST_STDOUT; then echo "✅ SGX report test passed"; else echo "❌ SGX report test failed"; fi
	@if grep -q "Success SGX quote" TEST_STDOUT; then echo "✅ SGX quote test passed"; else echo "❌ SGX quote test failed"; fi
endif

.PHONY: clean
clean:
	@echo "🧹 Cleaning up build artifacts..."
	@$(RM) *.manifest *.manifest.sgx *.sig OUTPUT* *.PID TEST_STDOUT TEST_STDERR
	@$(RM) -r scripts/__pycache__

.PHONY: distclean
distclean: clean
