# =============================================================================
# turbo_decoder_kr260.xdc
# -----------------------------------------------------------------------------
# Physical / timing constraints for the KR260 decoder demo (Kria K26 SOM
# xck26-sfvc784-2LV on the kr260_som carrier). See openspec/changes/add-fpga-
# kr260-decoder-port/design.md §3-§4 for the rationale; this is the Xilinx
# analog of the DE2 demo's .sdc + pin .qsf.
#
# What's pinned here:
#   1. PL clock (100 MHz / 10 ns). NOT constrained here: the zynq_ultra_ps_e
#      PS IP auto-generates the clock object on its pl_clk0 output (named
#      clk_pl_0 by the IP). Empirically confirmed on the first KR260 bitstream
#      build -- timing closed against clk_pl_0 @ 100.000 MHz with WNS +0.836 ns.
#      An explicit create_clock here is therefore both redundant (it would
#      double-define the same source) AND impossible to guard: XDC files are
#      read in a restricted mode that forbids Tcl control flow (`if`), so a
#      guarded create_clock raises "Command 'if' is not supported in the xdc"
#      (Designutils 20-1307) and is dropped anyway. We rely on the IP clock.
#   2. The two user LEDs (LEDS[0] / LEDS[1]) at the K26 SOM som240_1_d13 /
#      som240_1_d14 pins -- which the kr260_som part0_pins -> kr260_carrier
#      connection_map resolves to FPGA pins F8 / E8 respectively, both
#      LVCMOS18 (the K26 SOM VCCO bank powering these pins is 1.8 V).

# -----------------------------------------------------------------------------
# 1. PL clock from the PS (zynq_ultra_ps_e pl_clk0).
# -----------------------------------------------------------------------------
# Intentionally NO create_clock here. The PS IP constrains its own pl_clk0
# output (clk_pl_0 @ 100 MHz), which the BD's pl_clk0 net carries into the
# top-level `clk` via the kr260_clocking_wrapper instance. Adding a clock here
# is unnecessary and, because XDC forbids the `if` needed to guard it, would
# only emit a critical warning. If a future toolchain ever fails to derive the
# clock, add the constraint from a Tcl pre-hook (a .tcl source, NOT this .xdc)
# where control flow is allowed.

# -----------------------------------------------------------------------------
# 2. LED pin assignments (kr260_som part0_pins -> kr260_carrier connection_map).
# -----------------------------------------------------------------------------
#   LEDS[0] = User_led[0]  = som240_1_d13 = FPGA pin F8 (bank 66, VCCO 1.8 V)
#   LEDS[1] = User_led[1]  = som240_1_d14 = FPGA pin E8 (bank 66, VCCO 1.8 V)
# Pin numbers derived from the Vivado board files (xilinx.com:kr260_som:1.1
# and the kr260_carrier board file's connection_map). LVCMOS18 because bank
# 66 on the K26 SOM is fixed at VCCO = 1.8 V by the SOM voltage rail design.
set_property PACKAGE_PIN F8       [get_ports {LEDS[0]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {LEDS[0]}]
set_property PACKAGE_PIN E8       [get_ports {LEDS[1]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {LEDS[1]}]

# -----------------------------------------------------------------------------
# 3. False / async paths.
# -----------------------------------------------------------------------------
# This wrapper has NO async top-level inputs (no KEY/PB on this board for v1;
# the only "async" event is the PS reset deassertion, which proc_sys_reset
# already synchronizes to pl_clk0 before it leaves the BD). So no
# set_false_path constraints are needed.
