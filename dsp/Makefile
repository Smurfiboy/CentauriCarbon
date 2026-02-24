# CentauriCarbon — DSP (Xtensa HiFi4) build system
#
# Delegates to the oc-freertos-dsp submodule (dsp/oc-freertos-dsp/).
# Run `dsp/toolchain/fetch.sh` once to download the HiFi4 toolchain, then:
#
#   make              # build with default toolchain
#   make CROSS_COMPILE=<prefix>  # override compiler prefix
#   make V=1          # verbose output
#
# See dsp/oc-freertos-dsp/Makefile for the full list of options.

SUBMODULE_DIR := $(CURDIR)/oc-freertos-dsp

.PHONY: all clean

all clean:
	$(MAKE) -C $(SUBMODULE_DIR) $@
