#!/bin/bash
# CentauriCarbon — Xtensa HiFi4 DSP toolchain fetch script
#
# Downloads the pre-built Xtensa toolchain from the foss-xtensa project on
# GitHub (https://github.com/foss-xtensa/toolchain) and installs it into
# dsp/toolchain/ so that dsp/build.sh and dsp/Makefile can use it
# automatically.
#
# The toolchain used is the "test_kc705_hifi" HiFi4 reference configuration,
# which is the closest publicly available Xtensa GCC toolchain to the HiFi4
# core inside the Allwinner R528.  It allows the DSP firmware to be compiled
# and linked; for a binary that matches the exact R528 core (memory map,
# register-window config, etc.) you additionally need the proprietary LSP and
# core-pack files from the Allwinner / Cadence SDK.
#
# Usage:
#   ./fetch.sh               # install into dsp/toolchain/ (default)
#   ./fetch.sh -d <dir>      # install into a custom directory
#
# After running this script, dsp/build.sh and dsp/Makefile will detect the
# toolchain automatically.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Toolchain metadata ────────────────────────────────────────────────────────
TC_RELEASE="2020.07"
TC_VARIANT="xtensa-test_kc705_hifi-elf"
TC_ARCHIVE="x86_64-${TC_RELEASE}-${TC_VARIANT}.tar.gz"
TC_URL="https://github.com/foss-xtensa/toolchain/releases/download/${TC_RELEASE}/${TC_ARCHIVE}"
# SHA-512 checksum published on the foss-xtensa release page
TC_SHA512="389d4089af518b1065514adaf70b0ba577933513360af95847c1d05a2b9d5edb3e414ef081f923b11364ac828c87470edf2f9ceb3ff4a04830854f19131383c3"

# ── Default install directory ─────────────────────────────────────────────────
INSTALL_DIR="${SCRIPT_DIR}"

# ── Parse arguments ───────────────────────────────────────────────────────────
while getopts "d:" flag; do
    case "${flag}" in
        d) INSTALL_DIR="${OPTARG}";;
        *) echo "Usage: $0 [-d install_dir]"; exit 1;;
    esac
done

TC_BIN="${INSTALL_DIR}/${TC_RELEASE}/${TC_VARIANT}/bin"

# ── Check if already installed ────────────────────────────────────────────────
if [ -x "${TC_BIN}/${TC_VARIANT}-gcc" ]; then
    echo "Xtensa toolchain already installed at ${TC_BIN}"
    echo "  Compiler: ${TC_BIN}/${TC_VARIANT}-gcc"
    echo "  CROSS_COMPILE=${TC_VARIANT}-"
    exit 0
fi

echo "============================================================"
echo " Fetching Xtensa HiFi4 toolchain"
echo "   Release : ${TC_RELEASE}"
echo "   Variant : ${TC_VARIANT}"
echo "   Install : ${INSTALL_DIR}/${TC_RELEASE}/${TC_VARIANT}/"
echo "============================================================"

# ── Dependency checks ─────────────────────────────────────────────────────────
for cmd in curl sha512sum tar; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: required tool '${cmd}' not found in PATH"
        exit 1
    fi
done

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
if [ ! -x "${TC_BIN}/${TC_VARIANT}-gcc" ]; then
    echo "Error: extraction succeeded but compiler not found at expected path:"
    echo "  ${TC_BIN}/${TC_VARIANT}-gcc"
    exit 1
fi

echo ""
echo "============================================================"
echo " Xtensa HiFi4 toolchain installed successfully!"
echo ""
echo "  Compiler : ${TC_BIN}/${TC_VARIANT}-gcc"
echo "  Version  : $("${TC_BIN}/${TC_VARIANT}-gcc" --version 2>&1 | head -1)"
echo ""
echo " The DSP build scripts will detect this toolchain"
echo " automatically. You can now run:"
echo "   cd $(dirname "${SCRIPT_DIR}")"
echo "   ./build.sh"
echo "============================================================"
