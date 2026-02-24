# CentauriCarbon — DSP (Xtensa HiFi4) build system
#
# Analogous to mcu/Makefile.  Requires an Xtensa cross-compiler
# (e.g. xtensa-elf-gcc) accessible via PATH or the CROSS_COMPILE variable,
# plus the Allwinner R528 DSP SDK headers provided via SDK_DIR.
#
# Usage:
#   make                              # build with default xtensa-elf- prefix
#   make CROSS_COMPILE=xtensa-elf-    # explicit compiler prefix
#   make SDK_DIR=/path/to/r528-sdk    # path to Allwinner R528 DSP SDK
#   make V=1                          # verbose output

# Output directory
OUT = out/

# Project directory (R528 DSP0)
PROJ_DIR = projects/r528/dsp0

# Kconfig configuration
export KCONFIG_CONFIG := $(CURDIR)/.config
-include $(KCONFIG_CONFIG)

# Cross-compiler (Xtensa GNU toolchain — set CROSS_COMPILE or ensure the
# compiler is in PATH).  The Cadence XCC toolchain may be used by setting
# CROSS_COMPILE to the appropriate prefix (e.g. "xt-").
CROSS_COMPILE ?= xtensa-elf-
CC      := $(CROSS_COMPILE)gcc
AS      := $(CROSS_COMPILE)as
LD      := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
STRIP   := $(CROSS_COMPILE)strip
PYTHON  := python3

# Verbosity: run with "make V=1" to see compile commands
ifdef V
Q =
else
Q = @
MAKEFLAGS += --no-print-directory
endif

# ── Source files ─────────────────────────────────────────────────────────────
# Collect obj-y entries from the project Makefile without executing its
# clean rule.  All entries in that file are unconditional (obj-y +=).
obj-y := $(shell awk '/^obj-y[[:space:]]*\+=/{print $$NF}' $(PROJ_DIR)/Makefile)

SRCS := $(patsubst %.o,$(PROJ_DIR)/%.c,$(obj-y))
OBJS := $(patsubst $(PROJ_DIR)/%.c,$(OUT)%.o,$(SRCS))

# ── Compiler flags ────────────────────────────────────────────────────────────
# SDK_DIR should point to the Allwinner R528 DSP SDK root so that platform
# headers (console.h, platform.h, aw-alsa-lib/, etc.) can be found.
ifdef SDK_DIR
SDK_INCLUDES := \
    -I$(SDK_DIR)/include \
    -I$(SDK_DIR)/include/FreeRTOS \
    -I$(SDK_DIR)/components \
    -I$(SDK_DIR)/arch/$(patsubst "%",%,$(CONFIG_ARCH_PLATFORM))/include
else
SDK_INCLUDES :=
endif

CFLAGS := \
    -I$(OUT) \
    -I$(PROJ_DIR)/src/include \
    -I$(PROJ_DIR)/include \
    $(SDK_INCLUDES) \
    -std=gnu11 -O2 -MD \
    -Wall -ffunction-sections -fdata-sections

# ── Targets ───────────────────────────────────────────────────────────────────
TARGET_ELF := $(OUT)dsp0.elf
TARGET_BIN := $(OUT)dsp0.bin

.PHONY: all clean distclean

all: $(TARGET_ELF)

$(TARGET_ELF): $(OBJS)
	@echo "  Linking $@"
	$(Q)$(CC) $(OBJS) $(CFLAGS) -Wl,--gc-sections -o $@
	$(Q)$(OBJCOPY) -O binary $@ $(TARGET_BIN)
	@echo "  Built: $@"
	@echo "  Built: $(TARGET_BIN)"

$(OUT)%.o: $(PROJ_DIR)/%.c $(OUT)autoconf.h
	@mkdir -p $(dir $@)
	@echo "  Compiling $@"
	$(Q)$(CC) $(CFLAGS) -c $< -o $@

################ autoconf.h generation #######################################
# Generates autoconf.h from .config using a simple conversion script.
# The full Allwinner R528 DSP Kconfig hierarchy is not included in this
# repository, so kconfiglib/genconfig.py cannot be used here.

$(OUT)autoconf.h: $(KCONFIG_CONFIG) scripts/config2autoconf.py
	@echo "  Generating $@"
	$(Q)mkdir -p $(OUT)
	$(Q)$(PYTHON) scripts/config2autoconf.py $(KCONFIG_CONFIG) $@

################ Generic rules ###############################################

clean:
	$(Q)rm -rf $(OUT)

distclean: clean
	$(Q)rm -f .config .config.old

-include $(wildcard $(OUT)*.d $(OUT)src/*.d $(OUT)src/**/*.d)
