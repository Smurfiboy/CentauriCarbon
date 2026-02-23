# CentauriCarbon
Learn more about ELEGOO Centauri Carbon 3D printer: https://www.elegoo.com/products/centauri-carbon

This 3D printer system utilizes the Allwinner R528 chip as its main control platform, integrating a DSP unit and an MCU to provide a complete 3D printing solution.

The firmware serves as the core control module, encapsulating all 3D printing control algorithms and logic, including G-code parsing, motion path planning, temperature control strategies, auto-leveling, and time-lapse photography.

The DSP and MCU together form the system's real-time control core, responsible for managing a wide range of input/output signals and peripheral devices, such as multi-axis control of the printer, temperature monitoring and regulation of the heated bed and extruder, limit switch status detection, and fan speed control.

## Building

See [BUILD.md](BUILD.md) for detailed build instructions for each subsystem (Firmware, MCU, DSP).
