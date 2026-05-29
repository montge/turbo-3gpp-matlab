# =============================================================================
# program_kr260.tcl
# -----------------------------------------------------------------------------
# JTAG-download the KR260 decoder demo bitstream via Vivado Hardware Manager
# (the on-board FT4232H provides the JTAG link -- same cable as the UART
# console on COM4, different channel). The .bit comes from
# turbo_decoder_kr260_synth.tcl -mode bitstream. This script is the Xilinx
# analog of `quartus_pgm -c "USB-Blaster" -m jtag -o "p;..sof"`.
#
# Usage:
#   "D:/AMDDesignTools/2025.2.1/Vivado/bin/vivado.bat" -mode batch \
#       -source program_kr260.tcl -nojournal -nolog \
#       [ -tclargs -bit <path-to-.bit> ]
#
# Default .bit path is the location written by the bitstream mode of the synth
# TCL, resolved relative to this script.
# =============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize [file join $SCRIPT_DIR ../../..]]
set DEFAULT_BIT [file join $REPO_ROOT build kr260 proj kr260_demo.runs impl_1 \
                          turbo_decoder_kr260_top.bit]

set BIT $DEFAULT_BIT
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {$a eq "-bit"} {
        incr i
        set BIT [lindex $argv $i]
    }
}

if {![file exists $BIT]} {
    error "bitstream not found: $BIT (run turbo_decoder_kr260_synth.tcl -mode bitstream first)"
}

puts ""
puts "=== program_kr260.tcl ==="
puts "    BIT = $BIT"
puts ""

# Open Vivado Hardware Manager + start/connect the local hw_server (which
# wraps libxil/hardware over libftdi for the FT4232H on the KR260).
open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag

# A KR260's FT4232H typically enumerates as a single JTAG cable; open it and
# narrow to the Zynq UltraScale+ device. The K26 part is XCK26 (it appears in
# the JTAG chain under varying device names depending on the IDCODE). Pick the
# first device that matches xcu* (UltraScale+) or xck26 specifically.
open_hw_target

set devs [get_hw_devices]
puts "    JTAG chain: $devs"
set target_dev ""
foreach d $devs {
    set name [get_property NAME $d]
    if {[string match "*xck26*" $name] || [string match "*xczu*" $name]} {
        set target_dev $d
        break
    }
}
if {$target_dev eq ""} {
    # Fallback: just take the first device on the chain
    set target_dev [lindex $devs 0]
}
puts "    target device: $target_dev"
current_hw_device $target_dev

# Refresh device, set the program file, program.
refresh_hw_device -update_hw_probes false [current_hw_device]
set_property PROGRAM.FILE $BIT [current_hw_device]
program_hw_devices [current_hw_device]

puts ""
puts "=== programmed: $BIT ==="
puts ""

# Clean up.
close_hw_target
disconnect_hw_server
close_hw_manager
