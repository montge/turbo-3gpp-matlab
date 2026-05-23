# DE2 tx_chain_top board-demo timing constraints.
# Unlike the crc8 smoke (which was purely combinational), this demo is fully
# synchronous on the 50 MHz CLOCK_50, so we declare a REAL clock and let
# TimeQuest close setup/hold on the whole design.

# 50 MHz functional clock on the DE2 oscillator pin.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# Asynchronous, human-driven / display I/O: false-path them so TimeQuest does
# not flag the unconstrained async KEY input and the LED / 7-seg outputs.
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {LEDG[*]}]
set_false_path -to   [get_ports {HEX0[*]}]
set_false_path -to   [get_ports {HEX1[*]}]
