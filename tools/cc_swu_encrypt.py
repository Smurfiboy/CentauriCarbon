#!/usr/bin/env python3
"""
Pack a firmware update into the ELEGOO Centauri Carbon OTA .bin format.

Accepts either:
  - a ZIP file  (must contain the entry  update/update.swu)
  - a raw .swu  file  (it is wrapped into a ZIP automatically)

The output .bin has the following layout:
  [0x00 – 0x03]  4 bytes  – OTA magic  (0x14 0x17 0x0B 0x17)
  [0x04 – 0x07]  4 bytes  – firmware_info  (major, minor, patch, board_type)
  [0x08 – 0x0B]  4 bytes  – custom_info    (0x01 0x00 0x00 0x00)
  [0x0C – 0x0F]  4 bytes  – length of encrypted payload (LE uint32)
  [0x10 – 0x1F] 16 bytes  – MD5 of encrypted payload
  [0x20 – EOF ]  N bytes  – AES-256-CBC encrypted ZIP
                            (ZIP contains update/update.swu)

The resulting .bin can be:
  • placed as  update.bin  on a FAT32 USB stick (root level) for a local update
  • uploaded to the OTA server for an over-the-air update

Usage:
    python3 cc_swu_encrypt.py \\
        <input.swu|input.zip> <output.bin> \\
        [major] [minor] [patch] [board_type]

  major / minor / patch  – firmware version digits  (default: 0)
  board_type             – 0 = e100_lite / e100  (default: 0)

Examples:
    python3 cc_swu_encrypt.py update/update.swu update.bin 1 1 46
    python3 cc_swu_encrypt.py firmware.zip      update.bin 1 1 46 0
"""

import sys
import hashlib
import subprocess
import os
import struct
import zipfile

# AES-256-CBC key and IV hard-coded in the device firmware.
# These values are publicly documented (they are embedded in the printer's
# own application binary and have been reverse-engineered by the community).
# They provide integrity/obfuscation, NOT real confidentiality — treat any
# firmware package produced here as publicly readable by anyone who has the
# same key material.
_KEY = "78B6A614B6B6E361DC84D705B7FDDA33C967DDF2970A689F8156F78EFE0B1FCE"
_IV  = "54E37626B9A699403064111F77858049"

OTA_MAGIC   = bytes([0x14, 0x17, 0x0B, 0x17])
CUSTOM_INFO = bytes([0x01, 0x00, 0x00, 0x00])


def _pad16(data: bytes) -> bytes:
    """Pad data to the next 16-byte AES block boundary (zero-padding)."""
    remainder = len(data) % 16
    if remainder:
        data += b"\x00" * (16 - remainder)
    return data


def _wrap_swu_in_zip(swu_path: str) -> bytes:
    """Return the bytes of a ZIP archive containing update/update.swu."""
    import io
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(swu_path, "update/update.swu")
    return buf.getvalue()


def encrypt(
    inpath: str,
    outpath: str,
    major: int = 0,
    minor: int = 0,
    patch: int = 0,
    board: int = 0,
) -> None:

    # ── 1. Obtain ZIP bytes ──────────────────────────────────────────────────
    if inpath.endswith(".swu"):
        print(f"Wrapping {inpath} into a ZIP archive …")
        zip_bytes = _wrap_swu_in_zip(inpath)
    else:
        with open(inpath, "rb") as f:
            zip_bytes = f.read()
        # Sanity-check: the file should look like a ZIP
        if not zip_bytes[:2] == b"PK":
            raise ValueError(
                f"Input file does not look like a ZIP (magic={zip_bytes[:4].hex()})"
            )

    # ── 2. Pad to AES-256-CBC block size (16 bytes) ──────────────────────────
    zip_padded = _pad16(zip_bytes)

    # ── 3. Encrypt with AES-256-CBC (-nopad: we manage padding ourselves) ────
    tmp_plain = outpath + ".plain.tmp"
    tmp_enc   = outpath + ".enc.tmp"
    try:
        with open(tmp_plain, "wb") as f:
            f.write(zip_padded)

        result = subprocess.run(
            ["openssl", "enc", "-e", "-aes-256-cbc",
             "-in", tmp_plain, "-out", tmp_enc,
             "-K", _KEY, "-iv", _IV, "-nopad"],
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "openssl encryption failed:\n" + result.stderr.decode()
            )

        with open(tmp_enc, "rb") as f:
            encrypted = f.read()
    finally:
        for p in (tmp_plain, tmp_enc):
            if os.path.exists(p):
                os.unlink(p)

    # ── 4. Compute MD5 of encrypted payload ──────────────────────────────────
    # NOTE: MD5 is cryptographically weak; it is used here only because the
    # firmware file format requires it.  The hash verifies integrity against
    # accidental corruption, not authenticity.
    md5_digest = hashlib.md5(encrypted).digest()

    # ── 5. Build 32-byte header ───────────────────────────────────────────────
    firmware_info = bytes([major & 0xFF, minor & 0xFF, patch & 0xFF, board & 0xFF])
    enc_len       = struct.pack("<I", len(encrypted))

    header = OTA_MAGIC + firmware_info + CUSTOM_INFO + enc_len + md5_digest
    assert len(header) == 0x20, "Header must be exactly 32 bytes"

    # ── 6. Write output ───────────────────────────────────────────────────────
    with open(outpath, "wb") as f:
        f.write(header)
        f.write(encrypted)

    total = len(header) + len(encrypted)
    print(f"Version  : {major}.{minor}.{patch}  board={board}")
    print(f"ZIP size : {len(zip_bytes)} bytes  ({len(zip_padded)} after padding)")
    print(f"Enc size : {len(encrypted)} bytes")
    print(f"MD5      : {md5_digest.hex()}")
    print(f"Written  : {outpath}  ({total} bytes)")


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    inpath = sys.argv[1]
    outpath = sys.argv[2]
    major  = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    minor  = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    patch  = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    board  = int(sys.argv[6]) if len(sys.argv) > 6 else 0

    if not os.path.isfile(inpath):
        print(f"Error: input file not found: {inpath}", file=sys.stderr)
        sys.exit(1)

    encrypt(inpath, outpath, major, minor, patch, board)


if __name__ == "__main__":
    main()
