#!/bin/bash
# CentauriCarbon — DSP (Xtensa HiFi4) build script
#
# Builds the DSP firmware using the OpenCentauri FreeRTOS DSP submodule:
#   dsp/oc-freertos-dsp/  (https://github.com/OpenCentauri/oc-freertos-dsp)
#
# Usage:
#   ./build.sh             # build with auto-detected toolchain
#   ./build.sh -c <prefix> # override cross-compiler prefix
#
# Options:
#   -c <prefix>   Xtensa cross-compiler prefix.
#                 Defaults to the toolchain installed by toolchain/fetch.sh
#                 (dsp/oc-freertos-dsp/tools/xtensa-hifi4-gcc/bin/xtensa-hifi4-elf-)
#
# Prerequisites:
#   - git submodule update --init dsp/oc-freertos-dsp
#   - Run toolchain/fetch.sh once to download the HiFi4 GCC toolchain
#   - GNU make
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_DIR="${SCRIPT_DIR}/oc-freertos-dsp"

CROSS_COMPILE_ARG=""

while getopts "c:" flag; do
    case "${flag}" in
        c) CROSS_COMPILE_ARG="CROSS_COMPILE=${OPTARG}";;
        *) echo "Usage: $0 [-c cross_compile_prefix]"
           exit 1;;
    esac
done

# ── Ensure submodule is populated ─────────────────────────────────────────────
# We check for Makefile presence — this is the reliable portable test that
# works even outside a git context (e.g. in a tarball extraction).
if [ ! -f "${SUBMODULE_DIR}/Makefile" ]; then
    echo ""
    echo "Error: oc-freertos-dsp submodule is not initialised at:"
    echo "  ${SUBMODULE_DIR}"
    echo ""
    echo "Run one of the following from the repository root:"
    echo "  git submodule update --init dsp/oc-freertos-dsp"
    echo "  git submodule update --init --recursive"
    exit 1
fi

# ── Ensure toolchain is available ─────────────────────────────────────────────
TC_BIN="${SUBMODULE_DIR}/tools/xtensa-hifi4-gcc/bin"
if [ -z "${CROSS_COMPILE_ARG}" ] && [ ! -d "${TC_BIN}" ]; then
    echo ""
    echo "Error: HiFi4 toolchain not found at ${TC_BIN}"
    echo ""
    echo "Fetch the toolchain by running:"
    echo "  ${SCRIPT_DIR}/toolchain/fetch.sh"
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
cd "${SUBMODULE_DIR}"

# Pass CROSS_COMPILE only if the caller explicitly overrode it; otherwise the
# submodule's Makefile uses its own default (./tools/xtensa-hifi4-gcc/bin/…).
make -j"$(nproc)" ${CROSS_COMPILE_ARG}

# ── Copy outputs to dsp/out/ for OTA pipeline use ─────────────────────────────
# Resolve the objcopy binary to use (from the overridden or default toolchain).
if [ -n "${CROSS_COMPILE_ARG}" ]; then
    _OBJCOPY="$(echo "${CROSS_COMPILE_ARG}" | sed 's/CROSS_COMPILE=//')objcopy"
else
    _OBJCOPY="${TC_BIN}/xtensa-hifi4-elf-objcopy"
fi

mkdir -p "${SCRIPT_DIR}/out"
cp "${SUBMODULE_DIR}/build/dsp.elf" "${SCRIPT_DIR}/out/dsp0.elf"
"${_OBJCOPY}" -O binary "${SCRIPT_DIR}/out/dsp0.elf" "${SCRIPT_DIR}/out/dsp0.bin"

echo ""
echo "DSP build complete.  Output files:"
echo "  ${SUBMODULE_DIR}/build/dsp.elf"
echo "  ${SCRIPT_DIR}/out/dsp0.elf"
echo "  ${SCRIPT_DIR}/out/dsp0.bin  (raw binary for OTA dsp0 component)"
