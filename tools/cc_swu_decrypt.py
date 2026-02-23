#!/usr/bin/env python3
"""
Decrypt an ELEGOO Centauri Carbon OTA firmware .bin file into a ZIP archive.

The .bin format is:
  [0x00 – 0x03]  4 bytes  – OTA magic  (0x14 0x17 0x0B 0x17)
  [0x04 – 0x07]  4 bytes  – firmware_info  (major, minor, patch, board_type)
  [0x08 – 0x0B]  4 bytes  – custom_info
  [0x0C – 0x0F]  4 bytes  – length of encrypted payload (LE uint32)
  [0x10 – 0x1F] 16 bytes  – MD5 of encrypted payload
  [0x20 – EOF ]  N bytes  – AES-256-CBC encrypted ZIP
                            (ZIP contains update/update.swu)

Usage:
    python3 cc_swu_decrypt.py <firmware.bin> <output.zip>
"""

import sys
import hashlib
import subprocess
import os
import struct

# AES-256-CBC key and IV extracted from the Centauri Carbon device firmware.
# The key was derived from the Anycubic Kobra 2 Pro key by brute-forcing the
# last 3 bytes (same approach as the OpenCentauri cc-fw-tools project).
_KEY = "78B6A614B6B6E361DC84D705B7FDDA33C967DDF2970A689F8156F78EFE0B0928"
_IV  = "54E37626B9A699403064111F77858049"

HEADER_SIZE = 0x20          # 32 bytes
OTA_MAGIC   = bytes([0x14, 0x17, 0x0B, 0x17])


def decrypt(inpath: str, outpath: str) -> None:
    with open(inpath, "rb") as f:
        data = f.read()

    if len(data) < HEADER_SIZE:
        raise ValueError(f"File too small: {len(data)} bytes")

    magic        = data[0x00:0x04]
    firmware_ver = data[0x04:0x08]   # major, minor, patch, board_type
    custom_info  = data[0x08:0x0C]
    enc_len      = struct.unpack_from("<I", data, 0x0C)[0]
    stored_md5   = data[0x10:0x20]
    payload      = data[0x20:]

    if magic != OTA_MAGIC:
        raise ValueError(
            f"Bad magic: {magic.hex()} (expected {OTA_MAGIC.hex()})"
        )

    # NOTE: MD5 is cryptographically weak; it is used here only because the
    # firmware file format requires it.  This check verifies file integrity
    # (accidental corruption) but not authenticity.
    calc_md5 = hashlib.md5(payload).digest()
    if calc_md5 != stored_md5:
        raise ValueError(
            f"MD5 mismatch: stored={stored_md5.hex()} calculated={calc_md5.hex()}"
        )

    print(f"Magic    : {magic.hex()}")
    print(f"Version  : {firmware_ver[0]}.{firmware_ver[1]}.{firmware_ver[2]}"
          f"  board={firmware_ver[3]}")
    print(f"Enc len  : {enc_len} bytes (file has {len(payload)} bytes)")
    print(f"MD5 OK   : {stored_md5.hex()}")

    # Write encrypted payload to a temporary file then decrypt with openssl
    tmpfile = outpath + ".stage1.tmp"
    try:
        with open(tmpfile, "wb") as f:
            f.write(payload)

        result = subprocess.run(
            ["openssl", "enc", "-d", "-aes-256-cbc",
             "-in", tmpfile, "-out", outpath,
             "-K", _KEY, "-iv", _IV, "-nopad"],
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                "openssl decryption failed:\n" + result.stderr.decode()
            )
    finally:
        if os.path.exists(tmpfile):
            os.unlink(tmpfile)

    print(f"Decrypted: {outpath}")


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    inpath  = sys.argv[1]
    outpath = sys.argv[2]

    if not os.path.isfile(inpath):
        print(f"Error: input file not found: {inpath}", file=sys.stderr)
        sys.exit(1)

    decrypt(inpath, outpath)


if __name__ == "__main__":
    main()
