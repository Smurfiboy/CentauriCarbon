#!/bin/bash
# CentauriCarbon — DSP (Xtensa HiFi4) build script
#
# Builds the R528 DSP0 firmware image.
#
# Usage:
#   ./build.sh [-c <cross_compile>] [-s <sdk_dir>]
#
# Options:
#   -c <prefix>   Xtensa cross-compiler prefix.
#                 Defaults to the locally installed toolchain from
#                 toolchain/fetch.sh, or xtensa-elf- if not present.
#   -s <dir>      Path to Allwinner R528 DSP SDK root directory
#                 (needed for platform headers not included in this repo)
#
# Prerequisites:
#   - Xtensa toolchain — run toolchain/fetch.sh to download automatically
#   - GNU make
#   - python3
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CROSS_COMPILE_EXPLICIT=""
CROSS_COMPILE="xtensa-elf-"
SDK_DIR=""

while getopts "c:s:" flag; do
    case "${flag}" in
        c) CROSS_COMPILE="${OPTARG}"; CROSS_COMPILE_EXPLICIT="yes";;
        s) SDK_DIR="${OPTARG}";;
        *) echo "Usage: $0 [-c cross_compile_prefix] [-s sdk_dir]"
           exit 1;;
    esac
done

cd "$SCRIPT_DIR"

# ── Auto-detect local Xtensa toolchain (installed by toolchain/fetch.sh) ──────
# Use a version-agnostic glob so a toolchain upgrade only requires re-running
# toolchain/fetch.sh without editing this script.
LOCAL_TC_BIN="$(ls -d "${SCRIPT_DIR}"/toolchain/*/xtensa-test_kc705_hifi-elf/bin 2>/dev/null | head -1 || true)"
if [ -n "${LOCAL_TC_BIN}" ] && [ -z "${CROSS_COMPILE_EXPLICIT}" ]; then
    export PATH="${LOCAL_TC_BIN}:${PATH}"
    CROSS_COMPILE="xtensa-test_kc705_hifi-elf-"
    echo "Using local Xtensa toolchain: ${LOCAL_TC_BIN}"
fi

# Require a compiler to be available
if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo ""
    echo "Error: Xtensa compiler '${CROSS_COMPILE}gcc' not found in PATH."
    echo ""
    echo "Obtain the toolchain by running:"
    echo "  ${SCRIPT_DIR}/toolchain/fetch.sh"
    echo ""
    echo "Or pass a custom compiler prefix with -c:"
    echo "  $0 -c <cross_compile_prefix>"
    exit 1
fi

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
