#!/bin/bash
# =============================================================================
# CentauriCarbon — top-level build script
#
# Builds the MCU firmware (STM32F401) and the main firmware application
# (ARM Cortex-A7).  When a base firmware image is supplied via -s, the
# script also replaces the application binary inside the root filesystem and
# produces a complete update.bin compatible with the ELEGOO Centauri Carbon
# USB and OTA update format.
#
# Usage:
#   ./build.sh [-v <version>] [-p <project>] [-s <base.bin|base.swu>]
#
# Options:
#   -v <version>  Firmware version string, e.g. 1.1.46  (default: 1.0.0)
#   -p <project>  Project target: e100 or e100_lite      (default: e100_lite)
#   -s <path>     Path to a base firmware image (*.bin or *.swu).
#                 Required for creating a complete update.bin.
#                 A *.bin will be AES-decrypted automatically.
#                 A *.swu must be the raw SWUpdate CPIO archive.
#
# Full-packaging prerequisites (only needed when -s is provided):
#   cpio unsquashfs mksquashfs zip unzip openssl python3
#
# For a signing key compatible with the stock printer, see the OpenCentauri
# project (https://github.com/OpenCentauri/cc-fw-tools).
# Without a signing key the script writes update.swu unsigned; that update
# will only apply on printers that have been jailbroken to accept a custom
# or absent swupdate public-key certificate.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
TOOLS_DIR="$SCRIPT_DIR/tools"

# ── Defaults ─────────────────────────────────────────────────────────────────
VERSION="1.0.0"
TARGET="e100_lite"
BASE_IMG=""
SIGN_KEY="$SCRIPT_DIR/RESOURCES/KEYS/swupdate_private.pem"
ROOTFS_MAX_SIZE=$(( 128 * 1024 * 1024 ))   # 128 MiB — matches rootfsA/B partition size

# ── Parse arguments ───────────────────────────────────────────────────────────
while getopts "v:p:s:k:" flag; do
    case "${flag}" in
        v) VERSION=${OPTARG};;
        p) TARGET=${OPTARG};;
        s) BASE_IMG=${OPTARG};;
        k) SIGN_KEY=${OPTARG};;
        *) echo "Usage: $0 [-v version] [-p e100|e100_lite] [-s base.bin|base.swu] [-k signing.pem]"
           exit 1;;
    esac
done

if [[ ! $VERSION =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: version must be in x.y.z format (e.g. 1.1.46)"
    exit 1
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

mkdir -p "$OUT_DIR"

echo "============================================================"
echo " CentauriCarbon Build"
echo "   Version : $VERSION  (${MAJOR}.${MINOR}.${PATCH})"
echo "   Target  : $TARGET"
echo "   Base    : ${BASE_IMG:-<none – app & MCU only>}"
echo "============================================================"

# ── Step 1: MCU firmware (STM32F401) ─────────────────────────────────────────
echo ""
echo "=== [1/3] Building MCU firmware ==="
cd "$SCRIPT_DIR/mcu"
bash build.sh -v "$VERSION" -t sg
bash build.sh -v "$VERSION" -t extruder

# The build script produces upgrade_<target>_<version>.bin and a *_full_pack.bin
MCU_SG_UPGRADE="$SCRIPT_DIR/mcu/out/upgrade_sg_${VERSION}.bin"
MCU_EX_UPGRADE="$SCRIPT_DIR/mcu/out/upgrade_extruder_${VERSION}.bin"
MCU_SG_FULL="$SCRIPT_DIR/mcu/out/upgrade_sg_${VERSION}_full_pack.bin"
MCU_EX_FULL="$SCRIPT_DIR/mcu/out/upgrade_extruder_${VERSION}_full_pack.bin"

# Copy upgrade images so the firmware app bundles the freshly built versions
cp -v "$MCU_SG_UPGRADE" "$SCRIPT_DIR/firmware/resources/firmware/upgrade_sg.bin"
cp -v "$MCU_EX_UPGRADE" "$SCRIPT_DIR/firmware/resources/firmware/upgrade_extruder.bin"

cp -v "$MCU_SG_FULL" "$OUT_DIR/"
cp -v "$MCU_EX_FULL" "$OUT_DIR/"

# ── Step 2: Firmware application (ARM Cortex-A7) ─────────────────────────────
echo ""
echo "=== [2/3] Building firmware application ==="
export PATH="$SCRIPT_DIR/toolchain-sunxi-glibc/toolchain/bin:$PATH"
cd "$SCRIPT_DIR/firmware"
bash autoreleash.sh -p "$TARGET"

APP_BIN="$SCRIPT_DIR/firmware/build/app"
cp -v "$APP_BIN" "$OUT_DIR/app"

# ── Step 3: Package into update.bin ──────────────────────────────────────────
echo ""
if [ -z "$BASE_IMG" ]; then
    echo "=== [3/3] Packaging skipped — no -s <base> provided ==="
    echo ""
    echo "Artifacts in $OUT_DIR :"
    echo "  app                            — main firmware application"
    echo "  upgrade_sg_${VERSION}_full_pack.bin     — MCU sg full-pack"
    echo "  upgrade_extruder_${VERSION}_full_pack.bin — MCU extruder full-pack"
    echo ""
    echo "To build a complete update.bin, re-run with:"
    echo "  $0 -v $VERSION -p $TARGET -s path/to/base.bin"
    echo ""
    echo "See BUILD.md §'Full OTA packaging' for details."
    exit 0
fi

echo "=== [3/3] Packaging update.bin ==="

if [ ! -f "$BASE_IMG" ]; then
    echo "Error: base image not found: $BASE_IMG"
    exit 1
fi

# ── 3a. Obtain a raw update.swu from the base image ──────────────────────────
WORK_DIR="$OUT_DIR/swu_work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

BASE_EXT="${BASE_IMG##*.}"

if [ "$BASE_EXT" = "bin" ]; then
    echo "Decrypting base firmware (.bin → .zip) …"
    python3 "$TOOLS_DIR/cc_swu_decrypt.py" "$BASE_IMG" "$OUT_DIR/base.zip"
    echo "Extracting update/update.swu from ZIP …"
    unzip -o "$OUT_DIR/base.zip" -d "$OUT_DIR/base_extracted"
    rm -f "$OUT_DIR/base.zip"
    BASE_SWU="$OUT_DIR/base_extracted/update/update.swu"
elif [ "$BASE_EXT" = "swu" ]; then
    BASE_SWU="$BASE_IMG"
else
    echo "Error: unsupported base image extension '.$BASE_EXT'"
    echo "       Expected .bin (encrypted OTA package) or .swu (raw CPIO archive)"
    exit 1
fi

if [ ! -f "$BASE_SWU" ]; then
    echo "Error: could not locate update.swu at $BASE_SWU"
    exit 1
fi

# ── 3b. Unpack the CPIO archive ───────────────────────────────────────────────
echo "Unpacking base update.swu …"
cd "$WORK_DIR"
cpio -idv < "$BASE_SWU"

# Verify expected components
REQUIRED="sw-description boot-resource uboot boot0 kernel rootfs dsp0"
for f in $REQUIRED; do
    if [ ! -f "$f" ]; then
        echo "Error: component '$f' missing from base SWU"
        exit 1
    fi
done

# ── 3c. Replace rootfs application binary ────────────────────────────────────
echo "Replacing /app/app and MCU firmware in rootfs …"
unsquashfs -d squashfs-root rootfs

install -v -m 0755 "$OUT_DIR/app"          squashfs-root/app/app
install -v -m 0644 \
    "$SCRIPT_DIR/firmware/resources/firmware/upgrade_sg.bin" \
    squashfs-root/lib/firmware/upgrade_sg.bin
install -v -m 0644 \
    "$SCRIPT_DIR/firmware/resources/firmware/upgrade_extruder.bin" \
    squashfs-root/lib/firmware/upgrade_extruder.bin

# ── 3d. Rebuild squashfs rootfs ───────────────────────────────────────────────
echo "Rebuilding squashfs rootfs …"
rm -f rootfs
mksquashfs squashfs-root rootfs -comp xz -all-root

ROOTFS_SIZE=$(wc -c < rootfs)
if [ "$ROOTFS_SIZE" -ge $(( ROOTFS_MAX_SIZE + 1 )) ]; then
    echo "Error: rootfs is ${ROOTFS_SIZE} bytes, exceeds ${ROOTFS_MAX_SIZE}-byte partition limit"
    exit 1
fi

# ── 3e. Update sha256 hashes in sw-description ───────────────────────────────
echo "Updating sha256 hashes in sw-description …"
for component in boot-resource uboot boot0 kernel rootfs dsp0; do
    [ -f "$component" ] || continue
    hash_new=$(sha256sum "$component" | awk '{print $1}')
    hash_old=$(awk -F= '
        BEGIN{v=""}
        $1~"filename" {v=$2}
        $1~"sha256"   {
            gsub(/"| |;/,"",v)
            gsub(/"| |;/,"",$2)
            print v " " $2
        }' sw-description | grep "^${component} " | head -1 | awk '{print $2}')
    if [ -n "$hash_old" ]; then
        sed -i "s/${hash_old}/${hash_new}/g" sw-description
    else
        echo "Warning: no existing sha256 entry for '${component}' in sw-description"
    fi
done

# ── 3f. Rebuild cpio_item_md5 ─────────────────────────────────────────────────
echo "Rebuilding cpio_item_md5 …"
rm -f cpio_item_md5
for f in sw-description sw-description.sig boot-resource uboot boot0 kernel rootfs dsp0; do
    [ -f "$f" ] && md5sum "$f" >> cpio_item_md5
done

# ── 3g. Sign sw-description ───────────────────────────────────────────────────
if [ -f "$SIGN_KEY" ]; then
    echo "Signing sw-description with $SIGN_KEY …"
    rm -f sw-description.sig
    openssl dgst -sha256 -sign "$SIGN_KEY" sw-description > sw-description.sig
else
    echo "WARNING: signing key not found at $SIGN_KEY"
    echo "         The update will only apply on jailbroken printers."
    echo "         Place your private key there or use -k <path>"
fi

# ── 3h. Pack new update.swu (CPIO) ───────────────────────────────────────────
NEW_SWU="$OUT_DIR/update.swu"
echo "Packing new update.swu …"
for f in sw-description sw-description.sig \
         boot-resource uboot boot0 kernel rootfs dsp0 cpio_item_md5; do
    echo "$f"
done | cpio -ov -H crc > "$NEW_SWU"
echo "Created: $NEW_SWU"

# ── 3i. Zip and encrypt into update.bin ──────────────────────────────────────
echo "Creating update.bin …"

# Build the ZIP (update/update.swu inside)
mkdir -p "$OUT_DIR/update"
cp "$NEW_SWU" "$OUT_DIR/update/update.swu"
cd "$OUT_DIR"
rm -f update.zip
zip -r update.zip update/
rm -rf update/

# Encrypt
BOARD_TYPE=0   # 0 = e100 / e100_lite (PROJECT_BOARD_E100)
OUTPUT_BIN="$OUT_DIR/update_${TARGET}_${VERSION}.bin"
python3 "$TOOLS_DIR/cc_swu_encrypt.py" \
    "$OUT_DIR/update.zip" \
    "$OUTPUT_BIN" \
    "$MAJOR" "$MINOR" "$PATCH" "$BOARD_TYPE"
rm -f "$OUT_DIR/update.zip"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Build complete!"
echo ""
echo "  USB update (*.swu method):"
echo "    Copy  $NEW_SWU"
echo "    to    <usb-stick>/update/update.swu"
echo ""
echo "  USB update (.bin method) / OTA:"
echo "    Copy  $OUTPUT_BIN"
echo "    to    <usb-stick>/update.bin"
echo "    or upload to your OTA distribution service."
echo "============================================================"
