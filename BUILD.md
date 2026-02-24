# Build Instructions

This repository contains three independently buildable subsystems for the ELEGOO Centauri Carbon 3D printer. Each subsystem targets a different hardware component of the Allwinner R528 SoC platform.

| Subsystem | Directory | Target | Toolchain |
|-----------|-----------|--------|-----------|
| Firmware  | `firmware/` | ARM Cortex-A (R528 main CPU) | `arm-openwrt-linux-gcc` (included) |
| MCU       | `mcu/`      | STM32F401 (real-time MCU)   | `gcc-arm-none-eabi` (must be installed) |
| DSP       | `dsp/`      | Xtensa HiFi4 DSP (R528 DSP core) | `xtensa-hifi4-elf-gcc` (fetched by `dsp/toolchain/fetch.sh`) |

---

## 1. Firmware

The main application firmware runs on the ARM Cortex-A7 cores of the Allwinner R528. It is built with CMake using a pre-built OpenWrt cross-compiler that is already included in the repository.

### Prerequisites

- x86-64 Linux host (the bundled toolchain contains x86-64 ELF binaries)
- CMake ≥ 3.5
- `make`
- `getopt` (standard on Linux)

### Build steps

```bash
# 1. Add the bundled cross-compiler to PATH
export PATH="$PWD/toolchain-sunxi-glibc/toolchain/bin:$PATH"

# 2. Enter the firmware directory
cd firmware

# 3. Run the build script for the desired project target
#    Supported targets: e100, e100_lite
./autoreleash.sh -p e100_lite
```

The build script will:
1. Copy the matching `CMakeLists.txt.<target>` to `CMakeLists.txt`
2. Generate binary resource files (`translation.bin`, `widget.bin`) using the pre-built host tools in `tools/`
3. Create a `build/` directory, run `cmake`, and compile with `make -j19`

The resulting executable is written to `firmware/build/app`.

### Notes

- The compiler name expected by CMake is `arm-openwrt-linux-gcc`. Adding the toolchain's `bin/` directory to PATH (as shown above) makes it available.
- The static library `lib/ubToolenvLib.a` and all other pre-built shared libraries in `lib/` are ARM binaries that ship with the repository; they do not need to be built.
- The `ENABLE_MANUTEST` CMake option (`OFF` by default) can be turned on to include manufacturing-test code:
  ```bash
  cmake -DENABLE_MANUTEST=ON ..
  ```

---

## 2. MCU (STM32F401)

The MCU firmware is a Klipper-derived C project for the STM32F401 microcontroller. It uses a Kconfig + Make build system, the same approach used by the upstream Klipper project.

### Prerequisites

Install the following packages on a Debian/Ubuntu host:

```bash
sudo apt-get install \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    libnewlib-arm-none-eabi \
    libssl-dev \
    python3 \
    make
```

### Build steps

```bash
cd mcu

# Build firmware for the "sg" board, version 1.0.0
./build.sh -v 1.0.0 -t sg

# Or for the "extruder" board
./build.sh -v 1.0.0 -t extruder
```

Available board targets (each has its own directory under `mcu/board/`):
- `sg` — stepper / general board (STM32F401, 24 MHz crystal, USART2)
- `extruder` — extruder board (same MCU configuration)

The script will:
1. Copy `mcu/board/<target>/config/config` to `mcu/.config`
2. Run `make clean && make -j`
3. Compile `scripts/add_magic.c` (requires `libssl-dev`)
4. Produce the following output files inside `mcu/out/`:
   - `klipper.elf` / `klipper.bin` — raw firmware
   - `upgrade_<target>_<version>.bin` — signed upgrade image
   - `upgrade_<target>_<version>_full_pack.bin` — bootloader + upgrade image

### Notes

- A pre-configured `.config` for the STM32F401 is already committed to the repository. To change MCU settings, run `make menuconfig` from inside `mcu/`.
- The Klipper Python scripts (`scripts/`) require Python 3. Some tooling (e.g. `test_klippy.py`) additionally needs the packages listed in `scripts/klippy-requirements.txt`.

---

## 3. DSP (Xtensa HiFi4)

The DSP firmware runs on the Xtensa HiFi4 DSP core of the Allwinner R528. It is
provided by the **[OpenCentauri/oc-freertos-dsp](https://github.com/OpenCentauri/oc-freertos-dsp)**
submodule (`dsp/oc-freertos-dsp/`) — a community port of FreeRTOS for the R528 HiFi4 core.

### Toolchain

The correct toolchain is the purpose-built `xtensa-hifi4-elf` GCC, available via:

```bash
# Initialise the submodule if you haven't already
git submodule update --init dsp/oc-freertos-dsp

# Download the HiFi4 GCC toolchain (~60 MB) and install it into the submodule
dsp/toolchain/fetch.sh
```

This downloads `xtensa-hifi4-dsp.tar.gz` from
[github.com/YuzukiHD/FreeRTOS-HIFI4-DSP](https://github.com/YuzukiHD/FreeRTOS-HIFI4-DSP/releases/tag/Toolchains),
verifies its SHA-512 checksum, and extracts it into
`dsp/oc-freertos-dsp/tools/xtensa-hifi4-gcc/` — exactly where the submodule's
Makefile expects it.

### Prerequisites

- `git` (to initialise the submodule)
- `curl`, `sha512sum`, `tar` (for `toolchain/fetch.sh`)
- `make`

### Build steps

```bash
# 1. Initialise the DSP submodule (one-time)
git submodule update --init dsp/oc-freertos-dsp

# 2. Fetch the HiFi4 toolchain (one-time)
dsp/toolchain/fetch.sh

# 3. Build
cd dsp
./build.sh
```

Alternatively, using `make` directly from `dsp/`:

```bash
cd dsp
make

# Override cross-compiler prefix if needed:
make CROSS_COMPILE=xtensa-hifi4-elf-
```

The resulting firmware ELF is written to `dsp/oc-freertos-dsp/build/dsp.elf`.

### Deploying to the printer

See the [oc-freertos-dsp README](dsp/oc-freertos-dsp/README.md) for full
deployment instructions (USB-stick boot via U-Boot, etc.).

---

## Building All Components

Use the top-level `build.sh` script to build the MCU firmware and the main application in one step:

```bash
./build.sh -v 1.1.46 -p e100_lite
```

The script prints the location of all output files to `out/`.

### Full OTA packaging

To produce a complete `update.swu` + `update.bin` you need the OS-level
components (Linux kernel, bootloaders, squashfs root filesystem, DSP firmware)
which are **not** included in this repository.  There are two ways to supply
them:

**Prerequisites** (in addition to those listed in §1 and §2 above):

```bash
sudo apt-get install \
    cpio squashfs-tools zip unzip openssl python3
```

---

#### Option A — Use a pre-populated `RESOURCES/` directory (recommended)

This is the cleanest workflow if you have the component files already
extracted or want to keep them in a known location across builds.

1. **Populate `RESOURCES/components/`** — see
   [`RESOURCES/components/README.md`](RESOURCES/components/README.md)
   for detailed instructions.  In brief:

   ```bash
   # Download an official ELEGOO firmware release
   curl -L -o base.bin \
     "https://download.chitubox.com/chitusystems/chitusystems/public/printer/firmware/release/1/ca8e1d9a20974a5896f8f744e780a8a7/1/01.01.46/2025-10-22/f9bd2b9b1926408ca238de8e7eac69b6.bin"

   # Decrypt and unpack
   python3 tools/cc_swu_decrypt.py base.bin /tmp/base.zip
   unzip /tmp/base.zip -d /tmp/base_extracted

   # Extract all component files into RESOURCES/components/
   cd RESOURCES/components
   cpio -idv < /tmp/base_extracted/update/update.swu
   cd -
   ```

   After this step `RESOURCES/components/` will contain:
   `boot0`, `uboot`, `boot-resource`, `kernel`, `rootfs`, `dsp0`,
   `sw-description`.

2. **Optionally add a signing key** — see
   [`RESOURCES/KEYS/README.md`](RESOURCES/KEYS/README.md).

3. **Build:**

   ```bash
   ./build.sh -v 1.1.46 -p e100_lite -r RESOURCES/
   ```

   The script will:
   1. Build the MCU firmware (`sg` and `extruder` targets)
   2. Build the firmware application
   3. Copy the pre-placed component files into a working directory
   4. Inject the freshly built `app` and MCU firmware images into the rootfs
   5. Rebuild the squashfs rootfs (`mksquashfs -comp xz`)
   6. Update all sha256 hashes in `sw-description`
   7. Sign `sw-description` (if `RESOURCES/KEYS/swupdate_private.pem` exists)
   8. Repack everything into `out/update.swu`
   9. Zip and AES-256-CBC-encrypt into `out/update_e100_lite_1.1.46.bin`

---

#### Option B — Point to a base firmware image directly

If you prefer not to pre-extract the components, pass the base firmware
image directly:

```bash
./build.sh -v 1.1.46 -p e100_lite -s base.bin
```

`build.sh` will decrypt, unpack, and inject automatically — same pipeline as
Option A but extraction happens inline during the build.

---

4. Flash the resulting file:
   - **USB update (.bin method):** rename `out/update_e100_lite_1.1.46.bin`
     to `update.bin` and place it in the root of a FAT32 USB drive.
   - **USB update (.swu method):** copy `out/update.swu` to
     `<usb>/update/update.swu`.
   - **OTA:** upload `out/update_e100_lite_1.1.46.bin` to your distribution
     service.

### Firmware signing

`swupdate` on the printer verifies `sw-description` against the public key in `/etc/swupdate_public.pem`. Stock printers use the ELEGOO signing key; you cannot sign with a compatible key without access to the ELEGOO private key.

To flash custom firmware you have two options:

- **Jailbreak:** replace `/etc/swupdate_public.pem` on the printer with your own public key (see the [OpenCentauri project](https://github.com/OpenCentauri/cc-fw-tools) for guidance), then sign with your matching private key:

  ```bash
  # With pre-placed RESOURCES/
  ./build.sh -v 1.1.46 -p e100_lite -r RESOURCES/ -k path/to/private.pem

  # With a base image
  ./build.sh -v 1.1.46 -p e100_lite -s base.bin -k path/to/private.pem
  ```

- **Unsigned:** omit the key. `build.sh` will warn but continue; the resulting update will be rejected by stock firmware but accepted after jailbreaking.

### OTA packaging tools

Two Python helper scripts in `tools/` implement the encryption format:

| Script | Purpose |
|--------|---------|
| `tools/cc_swu_decrypt.py` | Decrypt an official `.bin` → `.zip` (for inspection or as a build base) |
| `tools/cc_swu_encrypt.py` | Encrypt a `.zip` or `.swu` → `.bin` (for USB/OTA distribution) |

**Decrypt example:**

```bash
python3 tools/cc_swu_decrypt.py firmware.bin firmware.zip
unzip firmware.zip -d firmware_extracted/
# firmware_extracted/update/update.swu is a CPIO archive
```

**Encrypt example:**

```bash
# From a raw .swu
python3 tools/cc_swu_encrypt.py update/update.swu update.bin 1 1 46

# From a ZIP already containing update/update.swu
python3 tools/cc_swu_encrypt.py firmware.zip update.bin 1 1 46 0
```

### Firmware update file format

The `.bin` file layout is:

```
Offset  Size  Description
──────  ────  ─────────────────────────────────────────────────────
0x00     4    Magic bytes: 0x14 0x17 0x0B 0x17
0x04     4    firmware_info: major, minor, patch, board_type
0x08     4    custom_info: 0x01 0x00 0x00 0x00
0x0C     4    Length of encrypted payload (little-endian uint32)
0x10    16    MD5 hash of encrypted payload
0x20     N    AES-256-CBC encrypted ZIP archive
               └── update/update.swu  (SWUpdate CPIO archive)
                    ├── sw-description        (libconfig metadata)
                    ├── sw-description.sig    (RSA-SHA256 signature)
                    ├── boot0                 (BROM first-stage loader)
                    ├── uboot                 (U-Boot second-stage loader)
                    ├── boot-resource         (boot splash / env resources)
                    ├── kernel                (Linux kernel + DTB image)
                    ├── rootfs                (squashfs root filesystem)
                    ├── dsp0                  (Xtensa HiFi4 DSP firmware)
                    └── cpio_item_md5         (MD5 manifest)
```

The pre-built MCU firmware images (`resources/firmware/upgrade_sg.bin`, `upgrade_extruder.bin`) that the firmware application bundles for OTA updates are already checked into the repository under `firmware/resources/firmware/` and do not need to be rebuilt unless the MCU firmware itself changes.
