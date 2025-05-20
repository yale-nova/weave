# Copyright (C) 2024 Gramine contributors
# SPDX-License-Identifier: BSD-3-Clause

ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)
ENCLAVE_HOME ?= $(patsubst %/,%,$(realpath $(dir $(lastword $(MAKEFILE_LIST)))))

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

# Variables to be passed via command line
WORKER_ID ?= $(shell hostname)
EXEC_ID ?= 0 
APP_ID ?= "app-default"
STACK_SIZE ?= "1M"
BRK_SIZE ?= "256M" 
SGX_ENCLAVE_SIZE ?= "6G"
SGX_MAX_THREADS ?= 64
FDS_LIMIT ?= 1024
DISABLE_ASLR ?= true
DISALLOW_SUBPROCESSES ?= false
ENABLE_SIGTERM ?= false
SPARK_HOME ?= /opt/spark
SGX_EDMM_ENABLE = true

# Logfile for Gramine loader/debugging
ENCLAVE_LOG_DIR ?= $(SPARK_HOME)/logs/enclave
GRAMINE_LOGFILE ?= $(ENCLAVE_LOG_DIR)/gramine_loader_$(WORKER_ID).log

.DEFAULT_GOAL := all

.PHONY: all
all: dirs java.manifest
ifeq ($(SGX),1)
all: java.manifest.sgx java.sig
endif

.PHONY: dirs
dirs:
	    mkdir -p /scratch/$(WORKER_ID) $(ENCLAVE_HOME)/data/$(WORKER_ID) $(SPARK_HOME)/logs/ $(ENCLAVE_LOG_DIR)

java.manifest: java.manifest.template
	    gramine-manifest \
	            -Denclave_home=$(ENCLAVE_HOME) \
	            -Dlog_level=$(GRAMINE_LOG_LEVEL) \
	            -Darch_libdir=$(ARCH_LIBDIR) \
	            -Dentrypoint=$(realpath $(shell sh -c "command -v java")) \
	            -Dstack_size=$(STACK_SIZE) \
	            -Dbrk_size=$(BRK_SIZE) \
	            -Dsgx_enclave_size=$(SGX_ENCLAVE_SIZE) \
	            -Dsgx_max_threads=$(SGX_MAX_THREADS) \
	            -Dfds_limit=$(FDS_LIMIT) \
	            -Ddisable_aslr=$(DISABLE_ASLR) \
	            -Ddisallow_subprocesses=$(DISALLOW_SUBPROCESSES) \
	            -Denable_sigterm=$(ENABLE_SIGTERM) \
	            -Dworker_id=$(WORKER_ID) \
	            -Dspark_home=$(SPARK_HOME) \
	            -Dloader_log_level=$(GRAMINE_LOG_LEVEL) \
	            -Dsgx_edmm_enable=$(SGX_EDMM_ENABLE) \
	            -Dlogfile_path=$(GRAMINE_LOGFILE) \
	            $< > $@

java.manifest.sgx java.sig: sgx_sign
	    @:

.INTERMEDIATE: sgx_sign
sgx_sign: java.manifest
	    gramine-sgx-sign \
	            --manifest $< \
	            --output $<.sgx

.PHONY: check
check: clean all

.PHONY: clean
clean:
	    $(RM) *.token *.sig *.manifest.sgx *.manifest

.PHONY: distclean
distclean: clean

is_in_container = \
	    grep -qE '/docker|/lxc|/kubepods' /proc/1/cgroup 2>/dev/null || \
	    [ -f /.dockerenv ] || \
	    [ "$$WEAVE_IN_CONTAINER" = "1" ]
