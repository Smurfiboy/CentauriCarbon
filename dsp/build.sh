#!/bin/bash
# CentauriCarbon — DSP (Xtensa HiFi4) build script
#
# Builds the R528 DSP0 firmware image.
#
# Usage:
#   ./build.sh [-c <cross_compile>] [-s <sdk_dir>]
#
# Options:
#   -c <prefix>   Xtensa cross-compiler prefix (default: xtensa-elf-)
#   -s <dir>      Path to Allwinner R528 DSP SDK root directory
#                 (needed for platform headers not included in this repo)
#
# Prerequisites:
#   - Xtensa toolchain (xtensa-elf-gcc or equivalent) in PATH or via -c
#   - GNU make
#   - python3
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CROSS_COMPILE="xtensa-elf-"
SDK_DIR=""

while getopts "c:s:" flag; do
    case "${flag}" in
        c) CROSS_COMPILE="${OPTARG}";;
        s) SDK_DIR="${OPTARG}";;
        *) echo "Usage: $0 [-c cross_compile_prefix] [-s sdk_dir]"
           exit 1;;
    esac
done

cd "$SCRIPT_DIR"

# Copy the R528 DSP0 defconfig to .config if .config is absent
if [ ! -f .config ]; then
    echo "No .config found — using R528 DSP0 defconfig"
    cp projects/r528/dsp0/defconfig .config
fi

# Build
MAKE_ARGS=("CROSS_COMPILE=${CROSS_COMPILE}")
if [ -n "$SDK_DIR" ]; then
    MAKE_ARGS+=("SDK_DIR=${SDK_DIR}")
fi

make clean
make -j"$(nproc)" "${MAKE_ARGS[@]}"

echo ""
echo "DSP build complete. Output files:"
echo "  ${SCRIPT_DIR}/out/dsp0.elf"
echo "  ${SCRIPT_DIR}/out/dsp0.bin"
