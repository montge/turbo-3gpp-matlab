# Altera DE1 placeholder

This directory is reserved for the DE1 wrapper and Quartus collateral for the observed Cyclone II `EP2C20F484C7N` FPGA target.

Use Quartus II `13.0sp1` on Windows or Linux for synthesis/programming. If Quartus device selection omits the lead-free `N` suffix, select `EP2C20F484C7`.

Keep macOS as the simulator host unless a VM or separate host provides the legacy Quartus toolchain.

The first board smoke interface should map switches or keys to a small input value and show CRC/status output on LEDs or seven-segment displays.
