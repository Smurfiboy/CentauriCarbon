#!/bin/bash
# CentauriCarbon — Xtensa HiFi4 DSP toolchain fetch script
#
# Downloads the pre-built xtensa-hifi4-elf GCC toolchain published by
# YuzukiHD / OpenCentauri at
#   https://github.com/YuzukiHD/FreeRTOS-HIFI4-DSP/releases/tag/Toolchains
#
# This is the same toolchain used by the oc-freertos-dsp submodule
# (dsp/oc-freertos-dsp/).  The submodule's Makefile expects the toolchain
# at <submodule-dir>/tools/xtensa-hifi4-gcc/, which is the default install
# location used by this script.
#
# Usage:
#   ./fetch.sh               # install into dsp/oc-freertos-dsp/tools/xtensa-hifi4-gcc/
#   ./fetch.sh -d <dir>      # install into a custom directory
#
# After running this script, dsp/build.sh will call make inside oc-freertos-dsp
# automatically.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Toolchain metadata ────────────────────────────────────────────────────────
TC_ARCHIVE="xtensa-hifi4-dsp.tar.gz"
TC_URL="https://github.com/YuzukiHD/FreeRTOS-HIFI4-DSP/releases/download/Toolchains/${TC_ARCHIVE}"
TC_COMPILER_PREFIX="xtensa-hifi4-elf-"
# SHA-512 of the released xtensa-hifi4-dsp.tar.gz
TC_SHA512="c155fd717d5948fc65e20658a32feb55c77fa8c49907a4389b051b39feaa1b9cc398028f7f3fc5bd8ccfa46596ea9bcd85a39ca4f7c861a8571313637542fda8"

# ── Default install directory ─────────────────────────────────────────────────
# The oc-freertos-dsp Makefile uses: CROSS_COMPILE ?= ./tools/xtensa-hifi4-gcc/bin/xtensa-hifi4-elf-
# So we install the toolchain into that directory by default.
SUBMODULE_DIR="${SCRIPT_DIR}/../oc-freertos-dsp"
INSTALL_DIR="${SUBMODULE_DIR}/tools/xtensa-hifi4-gcc"

# ── Parse arguments ───────────────────────────────────────────────────────────
while getopts "d:" flag; do
    case "${flag}" in
        d) INSTALL_DIR="${OPTARG}";;
        *) echo "Usage: $0 [-d install_dir]"; exit 1;;
    esac
done

# ── Check if already installed ────────────────────────────────────────────────
if [ -x "${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc" ]; then
    echo "Xtensa HiFi4 toolchain already installed at ${INSTALL_DIR}"
    echo "  Compiler: ${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc"
    exit 0
fi

echo "============================================================"
echo " Fetching Xtensa HiFi4 toolchain"
echo "   Source  : ${TC_URL}"
echo "   Install : ${INSTALL_DIR}"
echo "============================================================"

# ── Dependency checks ─────────────────────────────────────────────────────────
for cmd in curl sha512sum tar; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: required tool '${cmd}' not found in PATH"
        exit 1
    fi
done

# ── Check that the submodule has been initialised ─────────────────────────────
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

# ── Download ──────────────────────────────────────────────────────────────────
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

ARCHIVE_PATH="${TMPDIR_WORK}/${TC_ARCHIVE}"

echo ""
echo "Downloading ${TC_URL} ..."
curl -L --progress-bar -o "${ARCHIVE_PATH}" "${TC_URL}"

# ── Verify checksum ───────────────────────────────────────────────────────────
echo ""
echo "Verifying SHA-512 checksum ..."
ACTUAL_SHA512="$(sha512sum "${ARCHIVE_PATH}" | awk '{print $1}')"

if [ "${ACTUAL_SHA512}" != "${TC_SHA512}" ]; then
    echo "Error: checksum mismatch!"
    echo "  Expected : ${TC_SHA512}"
    echo "  Got      : ${ACTUAL_SHA512}"
    echo "The downloaded archive may be corrupt or tampered with."
    exit 1
fi
echo "  Checksum OK"

# ── Extract ───────────────────────────────────────────────────────────────────
echo ""
echo "Extracting to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${INSTALL_DIR}"

# ── Verify installation ───────────────────────────────────────────────────────
if [ ! -x "${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc" ]; then
    echo "Error: extraction succeeded but compiler not found at expected path:"
    echo "  ${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc"
    exit 1
fi

echo ""
echo "============================================================"
echo " Xtensa HiFi4 toolchain installed successfully!"
echo ""
echo "  Compiler : ${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc"
echo "  Version  : $("${INSTALL_DIR}/bin/${TC_COMPILER_PREFIX}gcc" --version 2>&1 | head -1)"
echo ""
echo " You can now build the DSP firmware by running:"
echo "   cd $(dirname "${SCRIPT_DIR}")"
echo "   ./build.sh"
echo "============================================================"
