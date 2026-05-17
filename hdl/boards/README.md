# Board bring-up notes

Board-specific Quartus projects, pin constraints, and top-level wrappers are intentionally deferred until the simulator-verified core interface is stable.

The first confirmed target is an Altera/Terasic DE2-class board with an observed Cyclone II `EP2C35F672C6N` FPGA marking. Terasic DE2 materials list the same board family with a Cyclone II `EP2C35F672C6` FPGA.

Cyclone II synthesis/programming should use the legacy Quartus II `13.0sp1` toolchain on Windows or Linux. macOS remains the local simulation host for GHDL/cocotb/GTKWave unless Quartus is run through a VM or separate host.

References:

- Terasic DE2 resources: https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=53&Language=English&No=30&PartNo=4
- Terasic DE2 board introduction: https://www.terasic.com.tw/attachment/archive/30/DE2_Introduction.pdf
- Intel Quartus device support table: https://www.intel.com/content/www/us/en/support/programmable/support-resources/design-software/devices-support.html
