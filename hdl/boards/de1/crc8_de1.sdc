# DE1 crc8 smoke timing constraints.
# The design is purely combinational (no functional clock); all I/O is
# asynchronous, human-driven switches and display outputs. These constraints
# document that intent and keep TimeQuest from flagging unconstrained paths.

derive_clock_uncertainty

set_false_path -from [get_ports {SW[*]}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {HEX0[*]}]
set_false_path -to   [get_ports {HEX1[*]}]
