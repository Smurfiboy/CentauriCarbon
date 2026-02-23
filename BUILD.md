# Build Instructions

This repository contains three independently buildable subsystems for the ELEGOO Centauri Carbon 3D printer. Each subsystem targets a different hardware component of the Allwinner R528 SoC platform.

| Subsystem | Directory | Target | Toolchain |
|-----------|-----------|--------|-----------|
| Firmware  | `firmware/` | ARM Cortex-A (R528 main CPU) | `arm-openwrt-linux-gcc` (included) |
| MCU       | `mcu/`      | STM32F401 (real-time MCU)   | `gcc-arm-none-eabi` (must be installed) |
| DSP       | `dsp/`      | Xtensa HiFi4 DSP (R528 DSP core) | Xtensa toolchain (must be obtained separately) |

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

The DSP firmware runs on the Xtensa HiFi4 DSP core of the Allwinner R528. It is structured as a Kconfig + Make project (similar to a Linux kernel driver tree).

### Prerequisites

An Xtensa toolchain for the HiFi4 core used in the Allwinner R528 is required. This toolchain is **not** included in the repository and must be obtained separately (e.g. from Cadence / Tensilica or via the Allwinner BSP SDK).

- Xtensa C/C++ compiler (`xt-xcc` or `xtensa-elf-gcc` depending on the variant)
- `make`
- Kconfig tools (already available in `mcu/lib/kconfiglib/` and can be reused if the toolchain supports Python-based Kconfig)

### Build steps

The DSP project follows the same Kconfig + Make pattern as the MCU:

```bash
cd dsp/projects

# Select the R528 DSP project configuration
# (equivalent to running "make menuconfig" and enabling PROJECT_R528 / CORE_DSP0)
# Then build:
make
```

> **Note:** A complete, standalone top-level DSP Makefile with Kconfig integration (equivalent to the one in `mcu/`) is not yet present in this repository. The `dsp/projects/` directory contains only the source-level Makefile hierarchy. A top-level Makefile that sets `CROSS_COMPILE`, invokes `genconfig`, and drives the `dsp/projects/` subtree is needed before the DSP component can be built end-to-end.

---

## Building All Components

There is currently no single top-level build script that builds all three components in one step. A suggested build order is:

1. **Firmware** — has no dependency on the MCU or DSP build outputs.
2. **MCU** — independent of firmware and DSP.
3. **DSP** — independent of firmware and MCU, but requires the external Xtensa toolchain.

The pre-built MCU firmware images (`resources/firmware/upgrade_sg.bin`, `upgrade_extruder.bin`) that the firmware application bundles for OTA updates are already checked into the repository under `firmware/resources/firmware/` and do not need to be rebuilt unless the MCU firmware itself changes.
